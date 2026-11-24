#!/usr/bin/env bash
# Pack the parts of the dataset into dist/release, one gzipped tar per part.
# The full tier is packed too when dist/full exists (see `just full`).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=dist/release
mkdir -p "$out"
tar czf "$out/ontology.tar.gz" ontology
tar czf "$out/vocab.tar.gz" vocab
tar czf "$out/data.tar.gz" data
tar czf "$out/rules.tar.gz" rules
tar czf "$out/fuseki.tar.gz" fuseki
if [ -d dist/full ]; then
  tar czf "$out/full.tar.gz" -C dist/full vocab data
fi
ls -l "$out"
