"""Fetch GBIF occurrences and monthly counts for the species list.

With species names as arguments, fetch only those species and replace their
rows in the existing files.

Writes etl/sources/gbif-occurrences.csv, etl/sources/gbif-monthly-counts.csv
and etl/sources/gbif-taxa.csv. Only CC0 and CC BY 4.0 records are used.
Run from the repository root: python3 etl/scripts/fetch_gbif.py
GBIF_PER_MONTH (default 2), GBIF_MAX_COUNTRIES (default 4) and GBIF_OUT
(default etl/sources) set the size of the pull and where it goes.
"""
import csv, json, os, random, sys, time, urllib.parse, urllib.request
from collections import defaultdict
from pathlib import Path

API = "https://api.gbif.org/v1"
COUNTRIES = ["NZ", "AU", "KR", "JP", "CN", "US", "CA", "GB", "ES", "ZA", "KE", "CL", "AR"]
MAX_COUNTRIES = int(os.environ.get("GBIF_MAX_COUNTRIES", 4))
PER_MONTH = int(os.environ.get("GBIF_PER_MONTH", 2))
YEARS = "2015,2025"
BASE = [("license", "CC0_1_0"), ("license", "CC_BY_4_0"), ("hasCoordinate", "true"),
        ("hasGeospatialIssue", "false"), ("occurrenceStatus", "PRESENT"), ("year", YEARS)]
OUT = Path(os.environ.get("GBIF_OUT", "etl/sources"))
# AviList name -> GBIF backbone name, where the backbone uses another name.
GBIF_NAMES = {"Anarhynchus bicinctus": "Charadrius bicinctus", "Strigops habroptilus": "Strigops habroptila"}


def get(path, params):
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                time.sleep(0.15)
                return json.load(r)
        except Exception as e:  # network or 429
            print("retry", attempt, url, e, file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(url)


def facet(params, field, limit=50):
    d = get("occurrence/search", params + [("limit", 0), ("facet", field), (f"{field}.facetLimit", limit)])
    out = {}
    for f in d.get("facets", []):
        for c in f["counts"]:
            out[c["name"]] = c["count"]
    return out


def main():
    rng = random.Random(42)
    species = list(csv.DictReader(open("etl/species-list.csv")))
    only = set(sys.argv[1:])
    if only:
        species = [s for s in species if s["scientific_name"] in only]
    taxa, occs, months = [], [], []
    for row in species:
        name = row["scientific_name"]
        m = get("species/match", [("name", GBIF_NAMES.get(name, name)), ("rank", "SPECIES"), ("class", "Aves")])
        key = m.get("acceptedUsageKey") or m.get("usageKey")
        taxa.append({"scientific_name": name, "gbif_key": key, "gbif_name": m.get("scientificName"),
                     "match_type": m.get("matchType")})
        if not key or m.get("rank") != "SPECIES":
            print("no match", name, file=sys.stderr)
            continue
        p = BASE + [("taxonKey", key)] + [("country", c) for c in COUNTRIES]
        by_country = facet(p, "country")
        chosen = sorted(by_country, key=lambda c: -by_country[c])[:MAX_COUNTRIES]
        for c in chosen:
            pc = BASE + [("taxonKey", key), ("country", c)]
            for mon, n in facet(pc, "month", 12).items():
                months.append({"scientific_name": name, "country": c, "month": mon, "count": n})
            results = []
            for offset in range(0, max(300, PER_MONTH * 150), 300):
                d = get("occurrence/search", pc + [("limit", 300), ("offset", offset)])
                results += d["results"]
                if d.get("endOfRecords"):
                    break
            by_month = defaultdict(list)
            for o in results:
                if o.get("month"):
                    by_month[o["month"]].append(o)
            for mon, rs in by_month.items():
                for o in rng.sample(rs, min(PER_MONTH, len(rs))):
                    occs.append({"gbif_id": o["key"], "scientific_name": name, "country": c,
                                 "event_date": o.get("eventDate", "")[:10], "year": o.get("year"),
                                 "month": o.get("month"), "lat": round(o["decimalLatitude"], 4),
                                 "lon": round(o["decimalLongitude"], 4),
                                 "uncertainty_m": o.get("coordinateUncertaintyInMeters", ""),
                                 "individual_count": o.get("individualCount", ""),
                                 "basis_of_record": o.get("basisOfRecord"),
                                 "dataset_key": o.get("datasetKey"), "license": o.get("license")})
        print(name, chosen, file=sys.stderr)
    OUT.mkdir(parents=True, exist_ok=True)
    for fname, rows in [("gbif-taxa.csv", taxa), ("gbif-occurrences.csv", occs), ("gbif-monthly-counts.csv", months)]:
        if only and (OUT / fname).exists():
            old = [r for r in csv.DictReader(open(OUT / fname)) if r["scientific_name"] not in only]
            rows = old + rows
        with open(OUT / fname, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]))
            w.writeheader()
            w.writerows(rows)


if __name__ == "__main__":
    main()
