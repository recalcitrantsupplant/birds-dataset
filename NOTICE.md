# Sources and attribution

The dataset combines the sources below. Each file in `data/` and `vocab/`
names its source with `dcterms:source`.

| Source | Used for | Licence | Citation |
| --- | --- | --- | --- |
| AviList v2025 | Taxonomy, English names, range text, Red List categories, protonyms | CC BY 4.0 | AviList Core Team. 2025. AviList: The Global Avian Checklist, v2025. https://doi.org/10.2173/avilist.v2025 |
| AVONET | Migration, habitat, trophic niche, lifestyle, body measurements, range centroid | CC BY 4.0 | Tobias, J.A. et al. 2022. AVONET: morphological, ecological and geographical data for all birds. Ecology Letters 25: 581–597. https://doi.org/10.1111/ele.13898. Data: https://figshare.com/articles/dataset/16586228 |
| GBIF occurrences | Occurrence points and monthly record counts | CC0 1.0 or CC BY 4.0, per record. Each occurrence names its licence and its GBIF dataset | GBIF.org occurrence search API, queried 2026-11-24. Each occurrence links to its GBIF record and dataset |
| Natural Earth 1:110m Admin 0 | Country boundaries | Public domain | Made with Natural Earth. https://www.naturalearthdata.com/ |
| UN M49 | Regions and subregions | Free to use | United Nations Statistics Division. https://unstats.un.org/unsd/methodology/m49/ |
| Authored for this dataset | Species accounts, sites, banded birds, resightings, food web, name changes, Māori names, vocabularies | CC BY 4.0 | This repository |

## Notes

- The AviList data was read from the CRAN package `avilistr` 0.0.1, which
  packages AviList v2025 unchanged.
- The Red List categories are as AviList v2025 reports them. They are not
  taken from the IUCN Red List directly.
- The site boundaries are approximate rectangles. Do not use them as legal or
  survey boundaries.
- The banded birds and their resightings are made up. They follow the real
  routes of each species, but no band number belongs to a real bird.
- The name changes are real changes, with the checklist that made each one.
  The assignment of old names to occurrences is made up.
- A GBIF derived-dataset DOI is still to do. It needs a GBIF account. See
  https://www.gbif.org/derived-dataset/about.
