# Recipes for the birds dataset. Run `just` to list them.

sqlib := env_var_or_default("SQLIB_CLI", "sqlib")

default:
    @just --list

# Install the Python packages that the scripts need.
setup:
    python3 -m pip install pandas pyreadr openpyxl rdflib shapely pyshacl

# Download AviList and AVONET, and extract the rows for the species list.
extract:
    python3 -I etl/scripts/extract_sources.py

# Fetch GBIF occurrences and monthly counts (about 40 minutes). Names fetch only those species.
fetch *species:
    python3 -I etl/scripts/fetch_gbif.py {{species}}

# Build vocab/*.ttl and data/*.ttl from etl/sources and etl/authored.
build:
    python3 -I etl/scripts/build.py

# Run the SRL rule sets and write rules/expected and data/inferred-traits.nt.
rules:
    SQLIB_CLI="{{sqlib}}" etl/scripts/run_rules.sh

# Validate the data against ontology/shapes.ttl.
validate:
    python3 -I etl/scripts/validate.py

# Build the full tier into dist/full: the whole AviList taxonomy and a larger GBIF pull.
full per_month="10" countries="13":
    mkdir -p dist/full/sources
    cp etl/sources/avilist.csv etl/sources/avonet.csv dist/full/sources/
    GBIF_OUT=dist/full/sources GBIF_PER_MONTH={{per_month}} GBIF_MAX_COUNTRIES={{countries}} python3 -I etl/scripts/fetch_gbif.py
    BIRDS_SOURCES=dist/full/sources BIRDS_OUT=dist/full BIRDS_FULL=1 python3 -I etl/scripts/build.py

# Pack each part into dist/release, one archive per part, for a release.
package:
    etl/scripts/package.sh
