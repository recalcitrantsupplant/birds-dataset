CREATE MACRO num(x) AS regexp_replace(round(x, 6)::VARCHAR, '\.0$', '');

WITH s AS (
  SELECT
    slug, name, country, site_type, description,
    CAST(lat AS DOUBLE) AS lat, CAST(lon AS DOUBLE) AS lon,
    CAST(half_lat AS DOUBLE) AS hl, CAST(half_lon AS DOUBLE) AS ho
  FROM read_csv('etl/authored/sites.csv', all_varchar = true)
)
SELECT
  slug AS siteKey,
  name,
  description,
  lower(country) AS countryKey,
  site_type AS siteType,
  lat::VARCHAR AS latitude,
  lon::VARCHAR AS longitude,
  format('POLYGON (({0} {1}, {0} {2}, {3} {2}, {3} {1}, {0} {1}))',
         num(lon + ho), num(lat - hl), num(lat + hl), num(lon - ho)) AS wkt
FROM s
