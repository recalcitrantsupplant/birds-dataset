CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

CREATE TEMP TABLE countries AS
SELECT iso2 FROM read_csv('etl/authored/countries.csv', all_varchar = true);

CREATE TEMP TABLE changes AS
SELECT row_number() OVER () AS n, from_name, to_name, country
FROM read_csv('etl/authored/name-changes.csv', all_varchar = true);

CREATE TEMP TABLE next_name AS
SELECT from_name, k.iso2 AS country, arg_min(to_name, n) AS to_name
FROM changes JOIN countries AS k ON changes.country IS NULL OR changes.country = k.iso2
GROUP BY ALL;

CREATE TEMP TABLE counts AS
SELECT scientific_name, country, CAST(month AS INTEGER) AS month, CAST(count AS BIGINT) AS count
FROM read_csv('etl/sources/gbif-monthly-counts.csv', all_varchar = true)
WHERE country IN (SELECT iso2 FROM countries);

CREATE TEMP TABLE resolved AS
WITH RECURSIVE chain(start, country, name, depth) AS (
  SELECT DISTINCT scientific_name, country, scientific_name, 0 FROM counts
  UNION ALL
  SELECT chain.start, chain.country, next_name.to_name, chain.depth + 1
  FROM chain JOIN next_name ON next_name.from_name = chain.name AND next_name.country = chain.country
  WHERE chain.depth < 20
)
SELECT start, country, arg_max(name, depth) AS name FROM chain GROUP BY ALL;

SELECT
  slug(r.name) AS speciesKey,
  lower(c.country) AS countryKey,
  c.month::VARCHAR AS month,
  max(c.count)::VARCHAR AS recordCount
FROM counts AS c
JOIN resolved AS r ON r.start = c.scientific_name AND r.country = c.country
WHERE r.name IN (
  SELECT Scientific_name FROM read_csv('etl/sources/avilist.csv', all_varchar = true) WHERE Taxon_rank = 'species'
)
GROUP BY ALL
ORDER BY ALL
