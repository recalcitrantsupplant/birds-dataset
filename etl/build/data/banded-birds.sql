CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

WITH species AS (
  SELECT Scientific_name AS name, English_name_AviList AS english
  FROM read_csv('etl/sources/avilist.csv', all_varchar = true) WHERE Taxon_rank = 'species'
),
sites AS (
  SELECT slug, name FROM read_csv('etl/authored/sites.csv', all_varchar = true)
),
r AS (
  SELECT row_number() OVER () AS line, lower(band) AS bandKey, *
  FROM read_csv('etl/authored/resightings.csv', all_varchar = true)
)
SELECT lower(band) AS bandKey, band AS bandNumber, slug(species) AS speciesKey, site AS bandingSiteKey,
       date AS bandingDate, colour_combination AS colours,
       NULL AS resightingKey, NULL AS resightingBandKey, NULL AS siteKey, NULL AS date, NULL AS previousPath, NULL AS note,
       band || ', ' || (SELECT english FROM species WHERE species.name = b.species) AS birdLabel,
       NULL AS resightingLabel
FROM read_csv('etl/authored/banded-birds.csv', all_varchar = true) AS b
UNION ALL
SELECT NULL, NULL, NULL, NULL, NULL, NULL,
       bandKey || '/' || seq, bandKey, site, date,
       coalesce('resighting/' || bandKey || '/' || lag(seq) OVER (PARTITION BY band ORDER BY line), 'bird/' || bandKey),
       note,
       NULL,
       band || ' at ' || (SELECT name FROM sites WHERE sites.slug = r.site) || ', ' || date
FROM r
