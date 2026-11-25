CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');
CREATE MACRO num(x) AS regexp_replace(round(x, 6)::VARCHAR, '\.0$', '');

CREATE TEMP TABLE countries AS
SELECT iso2 FROM read_csv('etl/authored/countries.csv', all_varchar = true);

CREATE TEMP TABLE species AS
SELECT Scientific_name AS name FROM read_csv('etl/sources/avilist.csv', all_varchar = true) WHERE Taxon_rank = 'species';

CREATE TEMP TABLE changes AS
SELECT row_number() OVER () AS n, from_name, to_name, country
FROM read_csv('etl/authored/name-changes.csv', all_varchar = true);

CREATE TEMP TABLE next_name AS
SELECT from_name, k.iso2 AS country, arg_min(to_name, n) AS to_name
FROM changes JOIN countries AS k ON changes.country IS NULL OR changes.country = k.iso2
GROUP BY ALL;

CREATE TEMP TABLE occ AS
SELECT * FROM (
  SELECT row_number() OVER () AS line, *
  FROM read_csv('etl/sources/gbif-occurrences.csv', all_varchar = true)
)
WHERE country IN (SELECT iso2 FROM countries) AND length(event_date) = 10
QUALIFY row_number() OVER (PARTITION BY gbif_id ORDER BY line) = 1;

CREATE TEMP TABLE resolved AS
WITH RECURSIVE chain(start, country, name, depth) AS (
  SELECT DISTINCT scientific_name, country, scientific_name, 0 FROM occ
  UNION ALL
  SELECT chain.start, chain.country, next_name.to_name, chain.depth + 1
  FROM chain JOIN next_name ON next_name.from_name = chain.name AND next_name.country = chain.country
  WHERE chain.depth < 20
)
SELECT start, country, arg_max(name, depth) AS name FROM chain GROUP BY ALL;

CREATE TEMP TABLE old_names AS
SELECT to_name, k.iso2 AS country, list(from_name ORDER BY n) AS names
FROM changes JOIN countries AS k ON changes.country IS NULL OR changes.country = k.iso2
GROUP BY ALL;

CREATE TEMP TABLE sites AS
SELECT slug, CAST(lat AS DOUBLE) AS lat, CAST(lon AS DOUBLE) AS lon,
       CAST(half_lat AS DOUBLE) AS hl, CAST(half_lon AS DOUBLE) AS ho
FROM read_csv('etl/authored/sites.csv', all_varchar = true);

WITH o AS (
  SELECT occ.*, r.name AS true_name, CAST(occ.gbif_id AS BIGINT) AS id,
         CAST(occ.lat AS DOUBLE) AS y, CAST(occ.lon AS DOUBLE) AS x
  FROM occ
  JOIN resolved AS r ON r.start = occ.scientific_name AND r.country = occ.country
  WHERE r.name IN (SELECT name FROM species)
),
identified AS (
  SELECT o.*,
    CASE
      WHEN o.scientific_name <> o.true_name THEN o.scientific_name
      WHEN old_names.names IS NOT NULL AND o.id % 3 = 0 THEN old_names.names[o.id % len(old_names.names) + 1]
    END AS identified_as
  FROM o LEFT JOIN old_names ON old_names.to_name = o.true_name AND old_names.country = o.country
)
SELECT
  i.gbif_id AS gbifId,
  slug(i.true_name) AS speciesKey,
  slug(i.identified_as) AS identifiedAsKey,
  lower(i.country) AS countryKey,
  i.event_date AS eventDate,
  i.month,
  i.year,
  i.basis_of_record AS basisOfRecord,
  CAST(CAST(i.individual_count AS DOUBLE) AS BIGINT)::VARCHAR AS individualCount,
  num(CAST(i.uncertainty_m AS DOUBLE)) AS uncertainty,
  'POINT(' || i.lon || ' ' || i.lat || ')' AS wkt,
  s.slug AS siteKey,
  i.dataset_key AS datasetKey,
  regexp_replace(replace(i.license, 'http://', 'https://'), 'legalcode$', '') AS license
FROM identified AS i
LEFT JOIN sites AS s ON i.x > s.lon - s.ho AND i.x < s.lon + s.ho AND i.y > s.lat - s.hl AND i.y < s.lat + s.hl
ORDER BY i.line
