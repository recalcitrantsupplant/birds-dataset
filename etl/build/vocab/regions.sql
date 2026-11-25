WITH ne AS (
  SELECT row_number() OVER () AS feature, ISO_A2, ISO_A2_EH, WB_A2, geometry::VARCHAR AS wkt
  FROM read_json('etl/sources/ne_110m_admin_0_countries.geojson')
),
codes AS (
  SELECT feature * 10 + 1 AS priority, ISO_A2 AS code, wkt FROM ne
  UNION ALL SELECT feature * 10 + 2, ISO_A2_EH, wkt FROM ne
  UNION ALL SELECT feature * 10 + 3, WB_A2, wkt FROM ne
),
geometry AS (
  SELECT code, arg_min(wkt, priority) AS wkt FROM codes WHERE code <> '-99' GROUP BY code
)
SELECT
  c.iso2,
  lower(c.iso2) AS countryKey,
  c.name,
  c.m49,
  c.region,
  c.region_name AS regionName,
  c.subregion,
  c.subregion_name AS subregionName,
  c.hemisphere,
  c.mi_name AS miName,
  g.wkt
FROM read_csv('etl/authored/countries.csv', all_varchar = true) AS c
JOIN geometry AS g ON g.code = c.iso2
