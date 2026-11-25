CREATE TEMP TABLE settings AS
SELECT CAST(per_month AS INTEGER) AS per_month, CAST(max_countries AS INTEGER) AS max_countries,
       string_split(countries, ' ') AS countries, years
FROM read_csv('etl/gbif.csv', all_varchar = true);

SET VARIABLE filters = (
  SELECT '&license=CC0_1_0&license=CC_BY_4_0&hasCoordinate=true&hasGeospatialIssue=false'
         || '&occurrenceStatus=PRESENT&year=' || url_encode(years)
  FROM settings
);
SET VARIABLE api = 'https://api.gbif.org/v1/';

CREATE TEMP TABLE species AS
SELECT s.scientific_name, coalesce(g.gbif_name, s.scientific_name) AS gbif_name,
       getvariable('api') || 'species/match?rank=SPECIES&class=Aves&name=' || url_encode(coalesce(g.gbif_name, s.scientific_name)) AS url
FROM read_csv('etl/.cache/fetch-species.csv', all_varchar = true) AS s
LEFT JOIN read_csv('etl/authored/gbif-names.csv', all_varchar = true) AS g ON g.avilist_name = s.scientific_name;

SET VARIABLE urls = (SELECT list(url) FROM species);
CREATE TEMP TABLE taxa AS
SELECT s.scientific_name, coalesce(m.acceptedUsageKey, m.usageKey) AS gbif_key, m.scientificName AS gbif_name,
       m.matchType AS match_type, m.rank
FROM species AS s
JOIN read_json(getvariable('urls'), filename = true,
               columns = {usageKey: 'BIGINT', acceptedUsageKey: 'BIGINT', scientificName: 'VARCHAR',
                          matchType: 'VARCHAR', rank: 'VARCHAR'}) AS m
  ON m.filename = s.url;

CREATE TEMP TABLE country_facet AS
SELECT t.scientific_name, t.gbif_key,
       getvariable('api') || 'occurrence/search?limit=0&facet=country&country.facetLimit=50&taxonKey=' || t.gbif_key
         || getvariable('filters') || '&country=' || array_to_string(st.countries, '&country=') AS url
FROM taxa AS t, settings AS st
WHERE t.rank = 'SPECIES';

SET VARIABLE urls = (SELECT list(url) FROM country_facet);
CREATE TEMP TABLE chosen AS
SELECT scientific_name, gbif_key, country FROM (
  SELECT f.scientific_name, f.gbif_key, c.name AS country, c.count,
         row_number() OVER (PARTITION BY f.scientific_name ORDER BY c.count DESC, c.position) AS position
  FROM country_facet AS f
  JOIN (
    SELECT filename, unnest(counts, recursive := true), generate_subscripts(counts, 1) AS position
    FROM (SELECT filename, unnest(facets).counts AS counts
          FROM read_json(getvariable('urls'), filename = true,
                         columns = {facets: 'STRUCT(field VARCHAR, counts STRUCT(name VARCHAR, count BIGINT)[])[]'}))
  ) AS c ON c.filename = f.url
)
WHERE position <= (SELECT max_countries FROM settings);

CREATE TEMP TABLE month_facet AS
SELECT ch.*, getvariable('api') || 'occurrence/search?limit=0&facet=month&month.facetLimit=12&taxonKey='
             || ch.gbif_key || '&country=' || ch.country || getvariable('filters') AS url
FROM chosen AS ch;

SET VARIABLE urls = (SELECT list(url) FROM month_facet);
CREATE TEMP TABLE months AS
SELECT f.scientific_name, f.country, c.name AS month, c.count
FROM month_facet AS f
JOIN (
  SELECT filename, unnest(counts, recursive := true)
  FROM (SELECT filename, unnest(facets).counts AS counts
        FROM read_json(getvariable('urls'), filename = true,
                       columns = {facets: 'STRUCT(field VARCHAR, counts STRUCT(name VARCHAR, count BIGINT)[])[]'}))
) AS c ON c.filename = f.url;

CREATE TEMP TABLE pages AS
SELECT ch.*, getvariable('api') || 'occurrence/search?limit=300&offset=' || o.start_at || '&taxonKey='
             || ch.gbif_key || '&country=' || ch.country || getvariable('filters') AS url
FROM chosen AS ch, settings AS st, range(0, greatest(300, st.per_month * 150), 300) AS o(start_at);

SET VARIABLE urls = (SELECT list(url) FROM pages);
CREATE TEMP TABLE records AS
SELECT p.scientific_name, p.country, r.*
FROM pages AS p
JOIN (
  SELECT filename, unnest(results, recursive := true)
  FROM read_json(getvariable('urls'), filename = true,
                 columns = {results: 'STRUCT(key BIGINT, eventDate VARCHAR, year INTEGER, month INTEGER,
                   decimalLatitude DOUBLE, decimalLongitude DOUBLE, coordinateUncertaintyInMeters DOUBLE,
                   individualCount INTEGER, basisOfRecord VARCHAR, datasetKey VARCHAR, license VARCHAR)[]'})
) AS r ON r.filename = p.url
WHERE r.month IS NOT NULL;

CREATE TEMP TABLE occurrences AS
SELECT key AS gbif_id, scientific_name, country, left(eventDate, 10) AS event_date, year, month,
       round(decimalLatitude, 4) AS lat, round(decimalLongitude, 4) AS lon,
       coordinateUncertaintyInMeters AS uncertainty_m, individualCount AS individual_count,
       basisOfRecord AS basis_of_record, datasetKey AS dataset_key, license
FROM records
QUALIFY row_number() OVER (PARTITION BY scientific_name, country, month ORDER BY hash(key))
        <= (SELECT per_month FROM settings);

COPY (
  SELECT * FROM read_csv('etl/sources/gbif-taxa.csv', all_varchar = true)
  WHERE scientific_name NOT IN (SELECT scientific_name FROM species)
  UNION ALL BY NAME
  SELECT scientific_name, gbif_key::VARCHAR AS gbif_key, gbif_name, match_type FROM taxa
) TO 'etl/sources/gbif-taxa.csv' (HEADER);

COPY (
  SELECT * FROM read_csv('etl/sources/gbif-occurrences.csv', all_varchar = true)
  WHERE scientific_name NOT IN (SELECT scientific_name FROM species)
  UNION ALL BY NAME
  SELECT COLUMNS(*)::VARCHAR FROM occurrences
) TO 'etl/sources/gbif-occurrences.csv' (HEADER);

COPY (
  SELECT * FROM read_csv('etl/sources/gbif-monthly-counts.csv', all_varchar = true)
  WHERE scientific_name NOT IN (SELECT scientific_name FROM species)
  UNION ALL BY NAME
  SELECT COLUMNS(*)::VARCHAR FROM months
) TO 'etl/sources/gbif-monthly-counts.csv' (HEADER);

SELECT 'gbif-taxa.csv' AS file, count(*)::VARCHAR AS rows, 'https://api.gbif.org/v1/species/match' AS source
FROM read_csv('etl/sources/gbif-taxa.csv', all_varchar = true)
UNION ALL
SELECT 'gbif-occurrences.csv', count(*)::VARCHAR, 'https://api.gbif.org/v1/occurrence/search'
FROM read_csv('etl/sources/gbif-occurrences.csv', all_varchar = true)
UNION ALL
SELECT 'gbif-monthly-counts.csv', count(*)::VARCHAR, 'https://api.gbif.org/v1/occurrence/search'
FROM read_csv('etl/sources/gbif-monthly-counts.csv', all_varchar = true)
