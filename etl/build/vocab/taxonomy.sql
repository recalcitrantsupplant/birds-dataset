CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

WITH a AS (
  SELECT * FROM read_csv('etl/sources/avilist.csv', all_varchar = true)
),
taxon AS (
  SELECT
    a.*,
    CAST(CAST(Sequence AS DOUBLE) AS BIGINT) AS seq,
    CASE Taxon_rank
      WHEN 'family' THEN "Order"
      WHEN 'genus' THEN Family
      WHEN 'species' THEN split_part(Scientific_name, ' ', 1)
    END AS parentName,
    CASE Taxon_rank
      WHEN 'family' THEN 'order'
      WHEN 'genus' THEN 'family'
      WHEN 'species' THEN 'genus'
    END AS parentRank
  FROM a
),
mi AS (
  SELECT scientific_name, name_mi FROM read_csv('etl/authored/vernacular-mi.csv', all_varchar = true)
),
gbif AS (
  SELECT scientific_name, gbif_key FROM read_csv('etl/sources/gbif-taxa.csv', all_varchar = true)
),
accounts AS (
  SELECT scientific_name, regexp_extract(account, '^(.*?[.!?])(\s|$)', 1) AS first_sentence
  FROM read_csv('etl/authored/accounts.csv', all_varchar = true)
),
changes AS (
  SELECT from_name, to_name, change_type FROM read_csv('etl/authored/name-changes.csv', all_varchar = true)
),
listed AS (
  SELECT Scientific_name AS name FROM taxon WHERE Taxon_rank = 'species'
),
-- Sister species that a split separated, when both are in the list: skos:related, both ways.
related AS (
  SELECT DISTINCT from_name AS name, to_name AS other FROM changes
  WHERE change_type = 'split' AND from_name IN (SELECT name FROM listed) AND to_name IN (SELECT name FROM listed)
  UNION
  SELECT DISTINCT to_name, from_name FROM changes
  WHERE change_type = 'split' AND from_name IN (SELECT name FROM listed) AND to_name IN (SELECT name FROM listed)
),
-- Earlier names of a listed species through genus moves and spelling changes: skos:hiddenLabel.
-- Splits and lumps are left out, because the earlier name there belongs to another taxon.
old_names AS (
  WITH RECURSIVE back(name, old, depth) AS (
    SELECT to_name, from_name, 1 FROM changes WHERE change_type IN ('genus-move', 'spelling')
    UNION ALL
    SELECT back.name, c.from_name, back.depth + 1
    FROM back JOIN changes AS c ON c.to_name = back.old AND c.change_type IN ('genus-move', 'spelling')
    WHERE back.depth < 20
  )
  SELECT DISTINCT name, old FROM back WHERE name IN (SELECT name FROM listed)
)
SELECT
  t.Taxon_rank AS rank,
  upper(left(t.Taxon_rank, 1)) || substr(t.Taxon_rank, 2) AS className,
  slug(t.Scientific_name) AS key,
  slug(p.Scientific_name) AS parentKey,
  CASE WHEN p.Scientific_name IS NULL THEN slug(t.Scientific_name) END AS topKey,
  t.seq::VARCHAR AS notation,
  t.Scientific_name AS scientificName,
  CASE WHEN t.Taxon_rank = 'species' THEN t.English_name_AviList ELSE t.Scientific_name END AS label,
  CASE WHEN t.Taxon_rank = 'family' THEN t.Family_English_name END AS familyName,
  CASE WHEN t.Taxon_rank = 'species' THEN t.Scientific_name END AS scientificAltLabel,
  CASE WHEN t.Taxon_rank = 'species' THEN mi.name_mi END AS miName,
  CASE WHEN t.Taxon_rank = 'species' AND strip_accents(mi.name_mi) <> mi.name_mi THEN strip_accents(mi.name_mi) END AS hiddenLabel,
  CASE WHEN t.Taxon_rank = 'species' THEN accounts.first_sentence END AS definition,
  CASE WHEN t.Taxon_rank = 'species' THEN 'https://www.gbif.org/species/' || gbif.gbif_key END AS exactMatch,
  NULL AS relatedKey,
  t.Authority AS authority,
  CASE WHEN t.Taxon_rank = 'species' THEN t.Range END AS rangeText,
  CASE WHEN t.Taxon_rank = 'species' THEN t.Protonym END AS protonym,
  CASE WHEN t.Taxon_rank = 'species' THEN t.Original_description_URL END AS seeAlso,
  CASE WHEN t.Taxon_rank = 'species' THEN t.AvibaseID END AS identifier,
  CASE WHEN t.Taxon_rank = 'species' THEN (t.Extinct_or_possibly_extinct IS NOT NULL)::VARCHAR END AS extinct,
  CASE WHEN t.Taxon_rank = 'species' THEN slug(t.Scientific_name) END AS nameKey
FROM taxon AS t
LEFT JOIN taxon AS p ON p.Taxon_rank = t.parentRank AND p.Scientific_name = t.parentName
LEFT JOIN mi ON mi.scientific_name = t.Scientific_name
LEFT JOIN gbif ON gbif.scientific_name = t.Scientific_name
LEFT JOIN accounts ON accounts.scientific_name = t.Scientific_name
UNION ALL BY NAME
-- One more row for each related species and each earlier name, with only the concept's key set.
SELECT slug(name) AS key, slug(other) AS relatedKey FROM related
UNION ALL BY NAME
SELECT slug(name) AS key, old AS hiddenLabel FROM old_names
ORDER BY CAST(notation AS BIGINT) NULLS LAST, key, relatedKey, hiddenLabel
