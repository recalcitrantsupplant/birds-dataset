#!/usr/bin/env bash
# Build vocab/*.ttl and data/*.ttl from etl/sources and etl/authored, with the
# sqlib ETL jobs in etl/build. Each job etl/build/<dir>/<name>.json writes
# <dir>/<name>.ttl. Also writes rules/expected/trait-inheritance-species.nt,
# the AVONET values that the rule set Trait inheritance must reproduce.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$root"

for job in etl/build/vocab/*.json etl/build/data/*.json; do
  out=${job#etl/build/}
  out=${out%.json}.ttl
  sqlib etl run --job "$job" --format turtle --out "$out"
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sqlib etl run --job etl/build/rules/expected/trait-inheritance-species.json --out "$tmp"
LC_ALL=C sort -u "$tmp" > rules/expected/trait-inheritance-species.nt
