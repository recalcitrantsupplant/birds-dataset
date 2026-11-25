CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

WITH changes AS (
  SELECT row_number() OVER () AS n, *
  FROM read_csv('etl/authored/name-changes.csv', all_varchar = true)
),
names AS (
  SELECT Scientific_name AS name FROM read_csv('etl/sources/avilist.csv', all_varchar = true) WHERE Taxon_rank = 'species'
  UNION SELECT from_name FROM changes
  UNION SELECT to_name FROM changes
)
SELECT slug(name) AS nameKey, name, NULL AS change, NULL AS fromKey, NULL AS toKey, NULL AS changeType,
       NULL AS countryKey, NULL AS checklist, NULL AS note
FROM names
UNION ALL
SELECT NULL, NULL, n::VARCHAR, slug(from_name), slug(to_name), change_type, lower(country), checklist, note
FROM changes
