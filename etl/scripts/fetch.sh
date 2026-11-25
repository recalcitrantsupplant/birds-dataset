#!/usr/bin/env bash
# Fetch GBIF occurrences and monthly counts into etl/sources with the job
# etl/extract/gbif.json. With species names as arguments, fetch only those
# species and keep the rows of the others. etl/gbif.csv sets the sample size.
# Run from a copy of the etl folder to write elsewhere (see full.sh).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p etl/.cache
if [ $# -gt 0 ]; then
  { echo scientific_name; printf '%s\n' "$@"; } > etl/.cache/fetch-species.csv
else
  cut -d, -f1 etl/species-list.csv > etl/.cache/fetch-species.csv
fi
sqlib etl run --job "$root/etl/extract/gbif.json" --allow-http --allow-extension-install --memory-limit 4GB \
  --format turtle --out etl/sources/gbif.ttl
