#!/usr/bin/env bash
# Load the dataset into the Kurrawong Fuseki image with fuseki/config.ttl,
# build both Lucene indexes, start the server and run a few queries against it.
# Each file is loaded into its own named graph, as the README describes.
# Exits non-zero on the first failed check. Needs Docker.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD

image=${FUSEKI_IMAGE:-ghcr.io/kurrawong/fuseki-lucene-shacl:sha-ff15690}
port=${CHECK_PORT:-3461}
name=birds-check-$$
volume=birds-check-$$
graph_base=https://example.org/birds/graph/

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm -f "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

java() {
  docker run --rm -e JAVA_TOOL_OPTIONS=-Xmx2g -v "$root:/b:ro" -v "$volume:/fuseki/databases" \
    --entrypoint java "$image" -cp /fuseki/jena-fuseki-server.jar "$@"
}

docker volume create "$volume" >/dev/null
echo "Image $image"

for f in ontology/*.ttl vocab/*.ttl data/*.ttl catalogue.ttl rules/expected/*.nt; do
  java tdb2.tdbloader --loc /fuseki/databases/birds --graph "$graph_base${f%.*}" "/b/$f" >/dev/null 2>&1
done
echo "Loaded $(ls ontology/*.ttl vocab/*.ttl data/*.ttl catalogue.ttl rules/expected/*.nt | wc -l) files, one graph each"

indexer_log=$(java org.apache.jena.query.text.cmd.shacltextindexer --desc=/b/fuseki/config.ttl 2>&1)
echo "$indexer_log" | grep -E "Index '.*' complete" || true

docker run -d --name "$name" -e JAVA_TOOL_OPTIONS=-Xmx2g -p "127.0.0.1:$port:3030" \
  -v "$root:/b:ro" -v "$volume:/fuseki/databases" \
  --entrypoint java "$image" -jar /fuseki/jena-fuseki-server.jar --config /b/fuseki/config.ttl >/dev/null
for _ in $(seq 60); do
  curl -sf "http://localhost:$port/\$/ping" >/dev/null && break
  sleep 1
done

query() {
  curl -sf "http://localhost:$port/birds/sparql" -H 'Accept: text/csv' \
    --data-urlencode "query=PREFIX luc: <urn:jena:lucene:index#> PREFIX skos: <http://www.w3.org/2004/02/skos/core#> PREFIX bird: <https://example.org/birds/def/> $1" \
    | tail -n +2 | tr -d '\r'
}

failed=0
check() {
  local label=$1 got=$2 want=$3
  if [[ "$got" == *"$want"* ]]; then
    echo "ok    $label"
  else
    echo "FAIL  $label: wanted '$want', got '${got//$'\n'/ | }'"
    failed=1
  fi
}

f=https://example.org/birds/index/field#
taxon=https://example.org/birds/vocab/taxon/

check "the union default graph has triples" \
  "$(query 'SELECT (IF(COUNT(*) > 0, "yes", "no") AS ?any) { ?s ?p ?o }')" "yes"

multi=$(echo "$indexer_log" | grep -c "Multiple values found" || true)
check "the indexer keeps every value of each field" "$multi warnings" "0 warnings"

check "an earlier scientific name finds the species" \
  "$(query "SELECT ?e { (?h ?e) luc:query (\"vocab\" \"[\\\"${f}label\\\"]\" \"\\\"Puffinus griseus\\\"\" \"\" \"\" 5 0) }")" \
  "${taxon}ardenna-grisea"

check "a Maori name without macrons finds the species" \
  "$(query "SELECT ?e { (?h ?e) luc:query (\"vocab\" \"[\\\"${f}label\\\"]\" \"kereru\" \"\" \"\" 5 0) }")" \
  "${taxon}hemiphaga-novaeseelandiae"

check "typeahead without macrons finds the species" \
  "$(query "SELECT ?e { (?h ?e) luc:query (\"vocab\" \"[\\\"${f}labelPrefix\\\"]\" \"kereru\" \"\" \"\" 5 0) }")" \
  "${taxon}hemiphaga-novaeseelandiae"

first_by_name=$(query 'SELECT ?s { ?s a bird:Species ; bird:scientificName ?n } ORDER BY ?n LIMIT 1')
check "sorting by scientific name puts the first species first" \
  "$(query "SELECT ?e { (?h ?e) luc:query (\"birds\" \"default\" \"*:*\" \"\" \"{\\\"field\\\":\\\"${f}scientificName\\\",\\\"order\\\":\\\"asc\\\",\\\"missing\\\":\\\"last\\\"}\" 1 0) }")" \
  "${first_by_name:-no species}"

check "the taxonomy hierarchy facets by order" \
  "$(query "SELECT ?v { (?fld ?v ?lo ?hi ?c) luc:facet (\"birds\" \"default\" \"\" \"[\\\"${f}order\\\"]\" \"\" 1 1) }")" \
  "${taxon}"

exit $failed
