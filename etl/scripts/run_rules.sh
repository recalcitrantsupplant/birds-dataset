#!/usr/bin/env bash
# Run each rule set in rules/ over the files it reads, and write its inferred
# triples to rules/expected/<rule set>.nt, sorted. Then check that the rule set
# Trait inheritance reproduces the AVONET values in
# rules/expected/trait-inheritance-species.nt, which build.sh writes.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$root"
tmp=$(mktemp -d -p "$root/etl/.cache" 2>/dev/null || mktemp -d)
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
  sqlib rules run --srl "rules/$rs.srl" --data "$tmp/$rs.ttl" --out "$tmp/$rs.nt" --max-iterations 20
  LC_ALL=C sort -u "$tmp/$rs.nt" > "rules/expected/$rs.nt"
done

expected=rules/expected/trait-inheritance-species.nt
awk 'NR == FNR { species[$1] = 1; next } ($1 in species) && $2 ~ /def\/effective(TrophicNiche|Habitat|Lifestyle)>$/' \
  "$expected" rules/expected/trait-inheritance.nt | LC_ALL=C sort -u > "$tmp/species.nt"
species=$(cut -d" " -f1 "$tmp/species.nt" | sort -u | grep -c .)
if ! LC_ALL=C comm -3 "$tmp/species.nt" "$expected" | grep -q .; then
  echo "trait-inheritance: the $species species values match AVONET"
else
  echo "trait-inheritance: the species values differ from AVONET:" >&2
  LC_ALL=C comm -3 "$tmp/species.nt" "$expected" | head -20 >&2
  exit 1
fi
