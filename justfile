# Recipes for the birds dataset. Run `just` to list them.
# Each recipe runs the sqlib command line: $SQLIB if it is set, or else the
# sqlib-cli Docker image (see etl/scripts/lib.sh).

default:
    @just --list

# Download AviList and AVONET, and extract the rows for the species list into etl/sources.
extract:
    etl/scripts/extract.sh

# Fetch GBIF occurrences and monthly counts into etl/sources. Names fetch only those species.
fetch *species:
    etl/scripts/fetch.sh {{species}}

# Build vocab/*.ttl and data/*.ttl from etl/sources and etl/authored.
build:
    etl/scripts/build.sh

# Run the SRL rule sets into rules/expected, and check trait inheritance against AVONET.
rules:
    etl/scripts/run_rules.sh

# Check vocab and data against ontology/shapes.ttl.
validate:
    etl/scripts/validate.sh

# Build the full tier into dist/full: the whole AviList taxonomy and a larger GBIF pull.
full per_month="10" countries="13":
    etl/scripts/full.sh {{per_month}} {{countries}}

# Pack each part into dist/release, one archive per part, for a release.
package:
    etl/scripts/package.sh
