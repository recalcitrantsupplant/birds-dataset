"""Extract the AviList and AVONET rows for the species list.

Downloads (once, into etl/.cache/):
- AviList v2025, from the CRAN package avilistr 0.0.1 (data CC BY 4.0).
- AVONET Supplementary dataset 1, Figshare article 16586228 (CC BY 4.0).
Writes etl/sources/avilist.csv (orders, families, genera and species of the
list) and etl/sources/avonet.csv (species traits, BirdLife taxonomy sheet).
Needs pandas, pyreadr and openpyxl.
"""
import csv, tarfile, urllib.request
from pathlib import Path

import pandas as pd
import pyreadr

CACHE = Path("etl/.cache")
AVILIST = "https://cran.r-project.org/src/contrib/avilistr_0.0.1.tar.gz"
AVONET = "https://ndownloader.figshare.com/files/34480856"
AVILIST_COLS = ["Sequence", "Taxon_rank", "Order", "Family", "Family_English_name", "Scientific_name",
                "Authority", "English_name_AviList", "Range", "Extinct_or_possibly_extinct",
                "IUCN_Red_List_Category", "AvibaseID", "Protonym", "Original_description_URL"]
# AviList name -> BirdLife v5 name, where AVONET uses another name.
BIRDLIFE_NAMES = {"Anarhynchus bicinctus": "Charadrius bicinctus", "Strigops habroptilus": "Strigops habroptila",
                  "Himantopus leucocephalus": "Himantopus himantopus", "Icthyophaga vocifer": "Haliaeetus vocifer"}
AVONET_COLS = ["Species1", "Family1", "Order1", "Avibase.ID1", "Beak.Length_Culmen", "Tarsus.Length",
               "Wing.Length", "Hand-Wing.Index", "Tail.Length", "Mass", "Habitat", "Habitat.Density",
               "Migration", "Trophic.Level", "Trophic.Niche", "Primary.Lifestyle", "Min.Latitude",
               "Max.Latitude", "Centroid.Latitude", "Centroid.Longitude", "Range.Size"]


def fetch(url, name):
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / name
    if not p.exists():
        urllib.request.urlretrieve(url, p)
    return p


def main():
    names = [r["scientific_name"] for r in csv.DictReader(open("etl/species-list.csv"))]
    tgz = fetch(AVILIST, "avilistr.tar.gz")
    with tarfile.open(tgz) as t:
        t.extract("avilistr/data/avilist_2025.rda", CACHE, filter="data")
    a = next(iter(pyreadr.read_r(CACHE / "avilistr/data/avilist_2025.rda").values()))
    a[AVILIST_COLS].to_csv(CACHE / "avilist-all.csv", index=False)
    sp = a[(a.Taxon_rank == "species") & a.Scientific_name.isin(names)]
    missing = set(names) - set(sp.Scientific_name)
    if missing:
        raise SystemExit(f"not in AviList: {sorted(missing)}")
    genera = {n.split()[0] for n in names}
    keep = a[((a.Taxon_rank == "order") & a.Scientific_name.isin(sp.Order))
             | ((a.Taxon_rank == "family") & a.Scientific_name.isin(sp.Family))
             | ((a.Taxon_rank == "genus") & a.Scientific_name.isin(genera))
             | ((a.Taxon_rank == "species") & a.Scientific_name.isin(names))]
    keep[AVILIST_COLS].to_csv("etl/sources/avilist.csv", index=False)

    x = fetch(AVONET, "avonet1.xlsx")
    av = pd.read_excel(x, sheet_name="AVONET1_BirdLife")
    av[AVONET_COLS].to_csv(CACHE / "avonet-all.csv", index=False)
    # AVONET uses BirdLife v5 names. Match on Avibase id first, then on name.
    ids = dict(zip(sp.Scientific_name, sp.AvibaseID))
    rows = []
    for n in names:
        m = av[av["Avibase.ID1"] == ids[n]]
        if m.empty:
            m = av[av.Species1 == BIRDLIFE_NAMES.get(n, n)]
        if m.empty:
            print("no AVONET row:", n)
            continue
        r = m.iloc[0][AVONET_COLS].to_dict()
        r["scientific_name"] = n
        rows.append(r)
    pd.DataFrame(rows).to_csv("etl/sources/avonet.csv", index=False)


if __name__ == "__main__":
    main()
