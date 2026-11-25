CREATE MACRO slug(s) AS trim(regexp_replace(lower(strip_accents(s)), '[^a-z0-9]+', '-', 'g'), '-');

SELECT slug(scientific_name) AS speciesKey,
       'trophic/' || CASE WHEN "Trophic.Niche" IN ('Omnivore', 'Scavenger') THEN 'niche-' ELSE '' END || slug("Trophic.Niche") AS trophicNiche,
       'habitat/' || slug(Habitat) AS habitat,
       'lifestyle/' || slug("Primary.Lifestyle") AS lifestyle
FROM read_csv('etl/sources/avonet.csv', all_varchar = true)
