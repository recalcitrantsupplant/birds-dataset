#!/usr/bin/env bash
# Run each rule set in rules/ over the files it reads, with the sqlib command
# line, and write its inferred triples to rules/expected/<rule set>.nt, sorted.
# Then copy the inferred traits to data/inferred-traits.nt for the Lucene index.
# SQLIB_CLI is the command, for example "node ../sqlib/packages/cli/dist/cli.js".
set -euo pipefail
cd "$(dirname "$0")/../.."
cli=${SQLIB_CLI:-sqlib}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

declare -A inputs=(
  [trait-inheritance]="vocab/taxonomy.ttl data/species.ttl"
  [name-resolution]="vocab/regions.ttl vocab/taxonomy.ttl data/names.ttl data/occurrences.ttl"
  [food-web]="vocab/concepts.ttl vocab/taxonomy.ttl data/food-web.ttl"
  [flyways]="data/sites.ttl data/banded-birds.ttl"
  [seasonal-status]="vocab/concepts.ttl vocab/regions.ttl data/monthly-counts.ttl"
)

mkdir -p rules/expected
for rs in "${!inputs[@]}"; do
  # shellcheck disable=SC2086
  cat ${inputs[$rs]} > "$tmp/$rs.ttl"
  $cli rules run --srl "rules/$rs.srl" --data "$tmp/$rs.ttl" --out "$tmp/$rs.nt" --max-iterations 20
  LC_ALL=C sort -u "$tmp/$rs.nt" > "rules/expected/$rs.nt"
done
cp rules/expected/trait-inheritance.nt data/inferred-traits.nt
