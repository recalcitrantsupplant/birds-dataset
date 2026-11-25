CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

CREATE TEMP TABLE taxon AS
SELECT
  Taxon_rank AS rank, Scientific_name AS name, English_name_AviList AS english, Family_English_name AS family_english,
  CAST(CAST(Sequence AS DOUBLE) AS BIGINT) AS seq,
  CASE Taxon_rank WHEN 'family' THEN "Order" WHEN 'genus' THEN Family WHEN 'species' THEN split_part(Scientific_name, ' ', 1) END AS parent_name,
  CASE Taxon_rank WHEN 'family' THEN 'order' WHEN 'genus' THEN 'family' WHEN 'species' THEN 'genus' END AS parent_rank
FROM read_csv('etl/.cache/avilist-all.csv', all_varchar = true)
WHERE Taxon_rank IN ('order', 'family', 'genus', 'species');

SELECT
  t.rank,
  upper(left(t.rank, 1)) || substr(t.rank, 2) AS className,
  slug(t.name) AS key,
  slug(p.name) AS parentKey,
  CASE WHEN p.name IS NULL THEN slug(t.name) END AS topKey,
  t.seq::VARCHAR AS notation,
  t.name AS scientificName,
  CASE WHEN t.rank = 'species' THEN t.english END AS englishName,
  CASE WHEN t.rank = 'species' AND t.english IS NOT NULL THEN t.name END AS scientificAltLabel,
  CASE WHEN t.rank <> 'species' OR t.english IS NULL THEN t.name END AS scientificLabel,
  CASE WHEN t.rank = 'family' THEN t.family_english END AS familyName
FROM taxon AS t
LEFT JOIN taxon AS p ON p.rank = t.parent_rank AND p.name = t.parent_name
ORDER BY t.seq
