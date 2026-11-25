CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

WITH r AS (
  SELECT row_number() OVER () AS line, lower(band) AS bandKey, *
  FROM read_csv('etl/authored/resightings.csv', all_varchar = true)
)
SELECT lower(band) AS bandKey, band AS bandNumber, slug(species) AS speciesKey, site AS bandingSiteKey,
       date AS bandingDate, colour_combination AS colours,
       NULL AS resightingKey, NULL AS resightingBandKey, NULL AS siteKey, NULL AS date, NULL AS previousPath, NULL AS note
FROM read_csv('etl/authored/banded-birds.csv', all_varchar = true)
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL,
       bandKey || '/' || seq, bandKey, site, date,
       coalesce('resighting/' || bandKey || '/' || lag(seq) OVER (PARTITION BY band ORDER BY line), 'bird/' || bandKey),
       note
FROM r
