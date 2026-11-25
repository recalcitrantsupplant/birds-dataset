#!/usr/bin/env bash
# Build the full tier into dist/full: the whole AviList taxonomy, and data from
# a larger GBIF pull. Arguments: records per month (default 10) and countries
# per species (default 13). Needs etl/.cache/avilist-all.csv from extract.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
per_month=${1:-10}
countries=${2:-13}
cd "$root"
full=dist/full
mkdir -p "$full/etl/.cache" "$full/vocab" "$full/data" "$full/rules/expected"
cp -r etl/authored etl/sources etl/species-list.csv "$full/etl/"
cp etl/.cache/avilist-all.csv "$full/etl/.cache/"
{ head -1 etl/gbif.csv; tail -n +2 etl/gbif.csv | awk -F, -v OFS=, -v p="$per_month" -v c="$countries" '{ $1 = p; $2 = c; print }'; } \
  > "$full/etl/gbif.csv"

cd "$full"
"$root/etl/scripts/fetch.sh"
for job in "$root"/etl/build/vocab/*.json "$root"/etl/build/data/*.json "$root"/etl/full/vocab/*.json; do
  out=${job#"$root"/etl/build/}
  out=${out#"$root"/etl/full/}
  sqlib etl run --job "$job" --format turtle --out "${out%.json}.ttl"
done
