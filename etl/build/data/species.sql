CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');
CREATE MACRO dec2(x) AS regexp_replace(round(CAST(x AS DOUBLE), 2)::VARCHAR, '\.0$', '');
CREATE MACRO trait_property(trait) AS
  CASE trait WHEN 'Trophic.Niche' THEN 'trophicNiche' WHEN 'Habitat' THEN 'habitat' ELSE 'lifestyle' END;
CREATE MACRO trait_concept(trait, value) AS
  CASE trait
    WHEN 'Trophic.Niche' THEN 'trophic/' || CASE WHEN value IN ('Omnivore', 'Scavenger') THEN 'niche-' ELSE '' END || slug(value)
    WHEN 'Habitat' THEN 'habitat/' || slug(value)
    ELSE 'lifestyle/' || slug(value)
  END;

CREATE TEMP TABLE taxon AS
SELECT Taxon_rank AS rank, Scientific_name AS name, "Order" AS order_name, Family AS family_name,
       CASE Taxon_rank WHEN 'species' THEN split_part(Scientific_name, ' ', 1) WHEN 'genus' THEN Scientific_name END AS genus_name
FROM read_csv('etl/sources/avilist.csv', all_varchar = true);

CREATE TEMP TABLE modes AS
UNPIVOT (SELECT * FROM read_csv('etl/sources/avonet-modes.csv', all_varchar = true))
ON "Trophic.Niche", Habitat, "Primary.Lifestyle" INTO NAME trait VALUE value;

CREATE TEMP TABLE avonet AS
SELECT * FROM read_csv('etl/sources/avonet.csv', all_varchar = true);

CREATE TEMP TABLE species_traits AS
UNPIVOT (SELECT scientific_name, "Trophic.Niche", Habitat, "Primary.Lifestyle" FROM avonet)
ON "Trophic.Niche", Habitat, "Primary.Lifestyle" INTO NAME trait VALUE value;

CREATE TEMP TABLE inherited AS
SELECT t.rank, t.name, tr.trait,
       om.value AS order_mode, fm.value AS family_mode, gm.value AS genus_mode, sv.value AS species_value
FROM taxon AS t
CROSS JOIN (VALUES ('Trophic.Niche'), ('Habitat'), ('Primary.Lifestyle')) AS tr(trait)
LEFT JOIN modes AS om ON om.rank = 'order' AND om.name = t.order_name AND om.trait = tr.trait
LEFT JOIN modes AS fm ON fm.rank = 'family' AND fm.name = t.family_name AND fm.trait = tr.trait AND t.rank <> 'order'
LEFT JOIN modes AS gm ON gm.rank = 'genus' AND gm.name = t.genus_name AND gm.trait = tr.trait
LEFT JOIN species_traits AS sv ON sv.scientific_name = t.name AND sv.trait = tr.trait AND t.rank = 'species';

CREATE TEMP TABLE stated AS
SELECT name, trait,
  CASE rank
    WHEN 'order' THEN order_mode
    WHEN 'family' THEN CASE WHEN family_mode IS DISTINCT FROM order_mode THEN family_mode END
    WHEN 'genus' THEN CASE WHEN genus_mode IS DISTINCT FROM coalesce(family_mode, order_mode) THEN genus_mode END
    WHEN 'species' THEN CASE WHEN species_value IS DISTINCT FROM coalesce(genus_mode, family_mode, order_mode) THEN species_value END
  END AS value
FROM inherited;

SELECT slug(name) AS taxonKey, trait_property(trait) AS traitProperty, trait_concept(trait, value) AS traitConcept,
       NULL AS speciesKey, NULL AS migration, NULL AS bodyMass, NULL AS wingLength, NULL AS beakLength,
       NULL AS tailLength, NULL AS handWingIndex, NULL AS rangeSize, NULL AS minLatitude, NULL AS maxLatitude,
       NULL AS centroid, NULL AS redListCategory, NULL AS account
FROM stated WHERE value IS NOT NULL
UNION ALL
SELECT NULL, NULL, NULL,
  slug(v.scientific_name),
  CASE CAST(CAST(v.Migration AS DOUBLE) AS INTEGER) WHEN 1 THEN 'sedentary' WHEN 2 THEN 'partial-migrant' WHEN 3 THEN 'migratory' END,
  dec2(v.Mass), dec2(v."Wing.Length"), dec2(v."Beak.Length_Culmen"), dec2(v."Tail.Length"),
  dec2(v."Hand-Wing.Index"), dec2(v."Range.Size"), dec2(v."Min.Latitude"), dec2(v."Max.Latitude"),
  printf('POINT(%.3f %.3f)', CAST(v."Centroid.Longitude" AS DOUBLE), CAST(v."Centroid.Latitude" AS DOUBLE)),
  lower(split_part(a.IUCN_Red_List_Category, ' ', 1)),
  acc.account
FROM avonet AS v
JOIN read_csv('etl/sources/avilist.csv', all_varchar = true) AS a
  ON a.Taxon_rank = 'species' AND a.Scientific_name = v.scientific_name
JOIN read_csv('etl/authored/accounts.csv', all_varchar = true) AS acc ON acc.scientific_name = v.scientific_name
