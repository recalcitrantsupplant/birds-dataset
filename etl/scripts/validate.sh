#!/usr/bin/env bash
# Check data/*.ttl and vocab/*.ttl against ontology/shapes.ttl with etl/checks/shacl-core.rq.
# The query covers the SHACL Core constraints that the shapes use. It writes one
# sh:ValidationResult per violation to etl/checks/report.ttl, and exits 1 if there is one.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$root"
data=()
for f in ontology/birds.ttl ontology/shapes.ttl vocab/*.ttl data/*.ttl; do data+=(--data "$f"); done
report=etl/checks/report.ttl
sqlib query --file etl/checks/shacl-core.rq "${data[@]}" --format n-triples --out "$report"
violations=$(grep -c 'ValidationResult' "$report" || true)
if [ "$violations" -gt 0 ]; then
  echo "$violations violations: see $report" >&2
  exit 1
fi
rm -f "$report"
echo "conforms"
