#!/usr/bin/env bash
# Download AviList v2025 and AVONET into etl/.cache, once, and extract the rows
# for etl/species-list.csv into etl/sources with the job etl/extract/avilist-avonet.json.
# AVILIST_URL is the AviList extended workbook (.xlsx).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$root"
mkdir -p etl/.cache
avilist_url=${AVILIST_URL:-https://www.avilist.org/wp-content/uploads/2025/06/AviList-v2025-11Jun-extended.xlsx}
[ -f etl/.cache/avilist.xlsx ] || curl -fsSL -o etl/.cache/avilist.xlsx "$avilist_url"
[ -f etl/.cache/avonet1.xlsx ] || curl -fsSL -o etl/.cache/avonet1.xlsx https://ndownloader.figshare.com/files/34480856
sqlib etl run --job etl/extract/avilist-avonet.json --allow-http --allow-extension-install \
  --format turtle --out etl/sources/avilist-avonet.ttl
