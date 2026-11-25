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
ORDER BY t.seq
