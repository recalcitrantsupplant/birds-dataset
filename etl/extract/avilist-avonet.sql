LOAD excel;

CREATE TEMP TABLE avilist AS
SELECT
  Sequence, Taxon_rank, "Order", Family, Family_English_name, Scientific_name, Authority,
  English_name_AviList, Range, Extinct_or_possibly_extinct, IUCN_Red_List_Category, AvibaseID,
  Protonym, Original_description_URL
FROM read_xlsx('etl/.cache/avilist.xlsx', all_varchar = true);

CREATE TEMP TABLE listed AS
SELECT l.line, a.* FROM avilist AS a
JOIN (SELECT row_number() OVER () AS line, scientific_name FROM read_csv('etl/species-list.csv', all_varchar = true)) AS l
  ON l.scientific_name = a.Scientific_name
WHERE a.Taxon_rank = 'species';

CREATE TEMP TABLE avonet AS
SELECT
  row_number() OVER () AS line,
  Species1, Family1, Order1, "Avibase.ID1",
  TRY_CAST("Beak.Length_Culmen" AS DOUBLE) AS "Beak.Length_Culmen",
  TRY_CAST("Tarsus.Length" AS DOUBLE) AS "Tarsus.Length",
  TRY_CAST("Wing.Length" AS DOUBLE) AS "Wing.Length",
  TRY_CAST("Hand-Wing.Index" AS DOUBLE) AS "Hand-Wing.Index",
  TRY_CAST("Tail.Length" AS DOUBLE) AS "Tail.Length",
  TRY_CAST(Mass AS DOUBLE) AS Mass,
  nullif(Habitat, 'NA') AS Habitat,
  TRY_CAST("Habitat.Density" AS INTEGER) AS "Habitat.Density",
  TRY_CAST(Migration AS INTEGER) AS Migration,
  nullif("Trophic.Level", 'NA') AS "Trophic.Level",
  nullif("Trophic.Niche", 'NA') AS "Trophic.Niche",
  nullif("Primary.Lifestyle", 'NA') AS "Primary.Lifestyle",
  TRY_CAST("Min.Latitude" AS DOUBLE) AS "Min.Latitude",
  TRY_CAST("Max.Latitude" AS DOUBLE) AS "Max.Latitude",
  TRY_CAST("Centroid.Latitude" AS DOUBLE) AS "Centroid.Latitude",
  TRY_CAST("Centroid.Longitude" AS DOUBLE) AS "Centroid.Longitude",
  TRY_CAST("Range.Size" AS DOUBLE) AS "Range.Size"
FROM read_xlsx('etl/.cache/avonet1.xlsx', sheet = 'AVONET1_BirdLife', all_varchar = true);

COPY (SELECT * FROM avilist) TO 'etl/.cache/avilist-all.csv' (HEADER);

COPY (
  SELECT * FROM avilist AS a
  WHERE (a.Taxon_rank = 'order' AND a.Scientific_name IN (SELECT "Order" FROM listed))
     OR (a.Taxon_rank = 'family' AND a.Scientific_name IN (SELECT Family FROM listed))
     OR (a.Taxon_rank = 'genus' AND a.Scientific_name IN (SELECT split_part(Scientific_name, ' ', 1) FROM listed))
     OR (a.Taxon_rank = 'species' AND a.Scientific_name IN (SELECT Scientific_name FROM listed))
) TO 'etl/sources/avilist.csv' (HEADER);

COPY (
  SELECT * EXCLUDE (line, priority, l_line) FROM (
    SELECT v.*, l.Scientific_name AS scientific_name, l.line AS l_line,
           CASE WHEN v."Avibase.ID1" = l.AvibaseID THEN 1 ELSE 2 END AS priority
    FROM listed AS l
    LEFT JOIN read_csv('etl/authored/birdlife-names.csv', all_varchar = true) AS b ON b.avilist_name = l.Scientific_name
    JOIN avonet AS v ON v."Avibase.ID1" = l.AvibaseID OR v.Species1 = coalesce(b.birdlife_name, l.Scientific_name)
    QUALIFY row_number() OVER (PARTITION BY l.Scientific_name ORDER BY priority, v.line) = 1
  )
  ORDER BY l_line
) TO 'etl/sources/avonet.csv' (HEADER);

CREATE TEMP TABLE groups AS
SELECT 'order' AS rank, Order1 AS name, line, "Trophic.Niche", Habitat, "Primary.Lifestyle" FROM avonet
UNION ALL SELECT 'family', Family1, line, "Trophic.Niche", Habitat, "Primary.Lifestyle" FROM avonet
UNION ALL SELECT 'genus', split_part(Species1, ' ', 1), line, "Trophic.Niche", Habitat, "Primary.Lifestyle" FROM avonet;

CREATE MACRO group_mode(trait) AS TABLE
SELECT rank, name, arg_min(value, sort) AS value FROM (
  SELECT rank, name, value, (-count(*)) * 1000000 + min(line) AS sort
  FROM (SELECT rank, name, line, COLUMNS(trait) AS value FROM groups)
  WHERE value IS NOT NULL
  GROUP BY ALL
)
GROUP BY ALL;

COPY (
  SELECT rank, name, t.value AS "Trophic.Niche", h.value AS Habitat, l.value AS "Primary.Lifestyle"
  FROM (SELECT DISTINCT rank, name FROM groups) AS g
  JOIN read_csv('etl/sources/avilist.csv', all_varchar = true) AS a ON a.Taxon_rank = g.rank AND a.Scientific_name = g.name
  LEFT JOIN group_mode('Trophic.Niche') AS t USING (rank, name)
  LEFT JOIN group_mode('Habitat') AS h USING (rank, name)
  LEFT JOIN group_mode('Primary.Lifestyle') AS l USING (rank, name)
  ORDER BY rank, name
) TO 'etl/sources/avonet-modes.csv' (HEADER);

SELECT 'avilist.csv' AS file, count(*)::VARCHAR AS rows, 'https://doi.org/10.2173/avilist.v2025' AS source
FROM read_csv('etl/sources/avilist.csv', all_varchar = true)
UNION ALL
SELECT 'avonet.csv', count(*)::VARCHAR, 'https://doi.org/10.6084/m9.figshare.16586228'
FROM read_csv('etl/sources/avonet.csv', all_varchar = true)
UNION ALL
SELECT 'avonet-modes.csv', count(*)::VARCHAR, 'https://doi.org/10.6084/m9.figshare.16586228'
FROM read_csv('etl/sources/avonet-modes.csv', all_varchar = true)
