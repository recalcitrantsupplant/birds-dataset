CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

WITH species AS (
  SELECT Scientific_name AS name FROM read_csv('etl/sources/avilist.csv', all_varchar = true) WHERE Taxon_rank = 'species'
)
SELECT
  slug(w.eater) AS eaterKey,
  CASE WHEN s.name IS NOT NULL THEN 'taxon' ELSE 'food' END AS foodScheme,
  slug(w.food) AS foodKey
FROM read_csv('etl/authored/food-web.csv', all_varchar = true) AS w
LEFT JOIN species AS s ON s.name = w.food
