"""Build the Turtle files of the dataset from etl/sources and etl/authored.

Writes vocab/*.ttl and data/*.ttl. Run from the repository root after
fetch_gbif.py and extract_sources.py: python3 etl/scripts/build.py
Needs pandas, rdflib and shapely.
"""
import csv, json, os, re, unicodedata
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd
from rdflib import BNode, Graph, Literal, Namespace, URIRef
from rdflib.namespace import DCTERMS, OWL, RDF, RDFS, SKOS, XSD
from shapely.geometry import Point, box, shape

BASE = "https://example.org/birds/"
BIRD = Namespace(BASE + "def/")
VOC = Namespace(BASE + "vocab/")
ID = Namespace(BASE + "id/")
GEO = Namespace("http://www.opengis.net/ont/geosparql#")
DWC = Namespace("http://rs.tdwg.org/dwc/terms/")
CC_BY = URIRef("https://creativecommons.org/licenses/by/4.0/")
# BIRDS_SOURCES and BIRDS_OUT let the full tier use a larger GBIF pull and write elsewhere.
SRC, AUTH = Path(os.environ.get("BIRDS_SOURCES", "etl/sources")), Path("etl/authored")
OUT = Path(os.environ.get("BIRDS_OUT", "."))
WKT = GEO.wktLiteral


def slug(s):
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def graph():
    g = Graph()
    for p, n in [("bird", BIRD), ("skos", SKOS), ("dcterms", DCTERMS), ("geo", GEO), ("dwc", DWC),
                 ("owl", OWL), ("xsd", XSD), ("rdfs", RDFS)]:
        g.bind(p, n)
    return g


def scheme(g, key, label, definition, source=None):
    s = VOC[key]
    g.bind(key.replace("-", ""), Namespace(f"{s}/"))
    g.add((s, RDF.type, SKOS.ConceptScheme))
    g.add((s, SKOS.prefLabel, Literal(label, lang="en")))
    g.add((s, SKOS.definition, Literal(definition, lang="en")))
    g.add((s, DCTERMS.license, CC_BY))
    if source:
        g.add((s, DCTERMS.source, URIRef(source)))
    return s


def concept(g, sch, key, label, definition=None, broader=None, notation=None, top=False, extra_type=None):
    c = URIRef(f"{sch}/{key}")
    g.add((c, RDF.type, SKOS.Concept))
    if extra_type:
        g.add((c, RDF.type, extra_type))
    g.add((c, SKOS.inScheme, sch))
    g.add((c, SKOS.prefLabel, Literal(label, lang="en")))
    if definition:
        g.add((c, SKOS.definition, Literal(definition, lang="en")))
    if notation is not None:
        g.add((c, SKOS.notation, Literal(str(notation))))
    if broader is not None:
        g.add((c, SKOS.broader, broader))
        g.add((broader, SKOS.narrower, c))
    if top or broader is None:
        g.add((sch, SKOS.hasTopConcept, c))
        g.add((c, SKOS.topConceptOf, sch))
    return c


def save(g, path):
    path = OUT / path
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    g.serialize(path, format="turtle")
    print(f"{path}: {len(g)} triples")


# ---------------------------------------------------------------- vocabularies

def small_vocabs():
    g = graph()
    v = {}
    s = scheme(g, "rank", "Taxonomic ranks", "The ranks of the taxonomy, from order to species.")
    v["rank"] = {r: concept(g, s, r, r.capitalize(), notation=i, top=True)
                 for i, r in enumerate(["order", "family", "genus", "species"], 1)}

    s = scheme(g, "migration", "Migration", "How far a species moves between seasons. The three categories of AVONET.",
               "https://doi.org/10.1111/ele.13898")
    v["migration"] = {
        1: concept(g, s, "sedentary", "Sedentary", "Most birds stay in or near their breeding area all year.", notation=1),
        2: concept(g, s, "partial-migrant", "Partial migrant", "Some birds of the species migrate and others stay.", notation=2),
        3: concept(g, s, "migratory", "Migratory", "Most birds of the species leave their breeding area for part of the year.", notation=3)}

    s = scheme(g, "habitat", "Habitats", "Primary habitats of AVONET, grouped as terrestrial or aquatic.",
               "https://doi.org/10.1111/ele.13898")
    terr = concept(g, s, "terrestrial", "Terrestrial", "Habitats on land.")
    aqua = concept(g, s, "aquatic", "Aquatic", "Habitats in or beside water.")
    v["habitat"] = {}
    for name, parent, d in [
            ("Forest", terr, "Closed forest."), ("Woodland", terr, "Open woodland and forest edge."),
            ("Shrubland", terr, "Scrub and heath."), ("Grassland", terr, "Grassland, savanna and tundra."),
            ("Desert", terr, "Desert and semi-desert."), ("Rock", terr, "Cliffs, scree and rocky ground."),
            ("Human Modified", terr, "Farmland, gardens and towns."),
            ("Wetland", aqua, "Marshes, swamps and lake margins."), ("Riverine", aqua, "Rivers and streams."),
            ("Coastal", aqua, "Beaches, estuaries and tidal flats."), ("Marine", aqua, "The open sea.")]:
        v["habitat"][name] = concept(g, s, slug(name), name, d, parent)

    s = scheme(g, "trophic", "Trophic niches", "What a species mainly eats: the trophic levels and trophic niches of AVONET.",
               "https://doi.org/10.1111/ele.13898")
    lv = {n: concept(g, s, slug(n), n, d) for n, d in [
        ("Herbivore", "Mainly plant food."), ("Carnivore", "Mainly animal food."),
        ("Omnivore", "Both plant and animal food."), ("Scavenger", "Mainly carrion.")]}
    v["trophic"] = {}
    for name, parent, d in [
            ("Frugivore", "Herbivore", "Mainly fruit."), ("Granivore", "Herbivore", "Mainly seeds."),
            ("Nectarivore", "Herbivore", "Mainly nectar."),
            ("Herbivore terrestrial", "Herbivore", "Mainly leaves, grass and roots on land."),
            ("Herbivore aquatic", "Herbivore", "Mainly aquatic plants and algae."),
            ("Invertivore", "Carnivore", "Mainly insects and other invertebrates."),
            ("Vertivore", "Carnivore", "Mainly land vertebrates."),
            ("Aquatic predator", "Carnivore", "Mainly fish and aquatic animals."),
            ("Omnivore", "Omnivore", "A mixed diet with no main source."),
            ("Scavenger", "Scavenger", "Mainly carrion.")]:
        key = "niche-" + slug(name) if name in ("Omnivore", "Scavenger") else slug(name)
        v["trophic"][name] = concept(g, s, key, name if key == slug(name) else f"{name} (niche)", d, lv[parent])

    s = scheme(g, "lifestyle", "Lifestyles", "Where a species spends most of its time when it forages. The five categories of AVONET.",
               "https://doi.org/10.1111/ele.13898")
    v["lifestyle"] = {n: concept(g, s, slug(n), n, d) for n, d in [
        ("Aerial", "Forages in flight."), ("Terrestrial", "Forages on the ground."),
        ("Insessorial", "Forages while perched in trees and shrubs."),
        ("Aquatic", "Forages on or in water."), ("Generalist", "Forages in several of these ways.")]}

    s = scheme(g, "red-list", "Red List categories", "Categories of extinction risk, as AviList v2025 reports them.")
    thr = concept(g, s, "threatened", "Threatened", "Critically endangered, endangered or vulnerable.")
    v["redlist"] = {}
    for code, name, parent in [("EX", "Extinct", None), ("CR", "Critically Endangered", thr), ("EN", "Endangered", thr),
                               ("VU", "Vulnerable", thr), ("NT", "Near Threatened", None), ("LC", "Least Concern", None),
                               ("DD", "Data Deficient", None), ("NE", "Not Evaluated", None)]:
        v["redlist"][code] = concept(g, s, code.lower(), name, notation=code, broader=parent)

    s = scheme(g, "season", "Seasons", "Seasons by hemisphere. Each season names its months.")
    v["hemisphere"] = {}
    for h, label in [("north", "Northern hemisphere"), ("south", "Southern hemisphere"), ("equatorial", "Equatorial")]:
        v["hemisphere"][h] = concept(g, s, h, label)
    seasons = {"north": [("spring", [3, 4, 5]), ("summer", [6, 7, 8]), ("autumn", [9, 10, 11]), ("winter", [12, 1, 2])],
               "south": [("spring", [9, 10, 11]), ("summer", [12, 1, 2]), ("autumn", [3, 4, 5]), ("winter", [6, 7, 8])]}
    v["season"] = {}
    for h, ss in seasons.items():
        for name, months in ss:
            pre = "boreal" if h == "north" else "austral"
            c = concept(g, s, f"{pre}-{name}", f"{pre.capitalize()} {name}", broader=v["hemisphere"][h])
            g.add((c, BIRD.hemisphere, v["hemisphere"][h]))
            g.add((c, BIRD.seasonName, Literal(name)))
            for m in months:
                g.add((c, BIRD.month, Literal(m)))
            v["season"][(h, name)] = c

    s = scheme(g, "seasonal-status", "Seasonal status", "How a species is present in a country through the year. A season counts as present when its GBIF records are at least a third of those of the busiest season.")
    for k, label, d in [("resident", "Resident", "Present in every season."),
                        ("summer-visitor", "Summer visitor", "Present in summer and absent in winter."),
                        ("winter-visitor", "Winter visitor", "Present in winter and absent in summer."),
                        ("passage-migrant", "Passage migrant", "Present in spring or autumn only."),
                        ("summer-and-winter", "Summer and winter", "Present in summer and winter, absent in spring or autumn.")]:
        concept(g, s, k, label, d)

    s = scheme(g, "site-type", "Site types", "Kinds of site where birds gather.")
    v["site_type"] = {k: concept(g, s, k, k.replace("-", " ").capitalize()) for k in
                      ["tidal-flat", "estuary", "braided-river", "wetland", "lake", "coast", "bottleneck"]}

    s = scheme(g, "name-change", "Name change types", "Kinds of change to a scientific name between checklists.")
    v["change"] = {k: concept(g, s, k, label, d) for k, label, d in [
        ("genus-move", "Genus move", "The species moved to another genus."),
        ("split", "Split", "One species became two or more. The change applies in one region."),
        ("lump", "Lump", "Two or more species became one."),
        ("spelling", "Spelling", "The spelling of the name changed.")]}

    s = scheme(g, "food", "Food resources", "Kinds of food that are not bird species, for the food web.")
    v["food"] = {}
    for r in csv.DictReader(open(AUTH / "food-resources.csv")):
        v["food"][r["slug"]] = concept(g, s, r["slug"], r["label"], r["definition"],
                                      v["food"].get(r["broader"]), extra_type=BIRD.FoodResource)
    save(g, "vocab/concepts.ttl")
    return v


def regions():
    g = graph()
    s = scheme(g, "region", "Regions and countries", "UN M49 regions and subregions, and the countries of the dataset. Boundaries from Natural Earth 1:110m (public domain).",
               "https://unstats.un.org/unsd/methodology/m49/")
    ne = json.load(open("etl/sources/ne_110m_admin_0_countries.geojson"))
    geoms = {}
    for f in ne["features"]:
        p = f["properties"]
        for k in ("ISO_A2", "ISO_A2_EH", "WB_A2"):
            if p.get(k) and p[k] != "-99":
                geoms.setdefault(p[k], shape(f["geometry"]))
    c = {}
    shapes = {}
    for r in csv.DictReader(open(AUTH / "countries.csv")):
        reg = concept(g, s, f"m49-{r['region']}", r["region_name"], notation=r["region"])
        sub = concept(g, s, f"m49-{r['subregion']}", r["subregion_name"], broader=reg, notation=r["subregion"])
        k = concept(g, s, r["iso2"].lower(), r["name"], broader=sub, notation=r["iso2"], extra_type=BIRD.Country)
        g.add((k, RDF.type, GEO.Feature))
        if r["mi_name"]:
            g.add((k, SKOS.altLabel, Literal(r["mi_name"], lang="mi")))
        g.add((k, BIRD.region, reg))
        g.add((k, BIRD.hemisphere, VOC[f"season/{r['hemisphere']}"]))
        g.add((k, DCTERMS.identifier, Literal(r["m49"])))
        geom = geoms[r["iso2"]]
        gn = URIRef(f"{k}/geometry")
        g.add((k, GEO.hasGeometry, gn))
        g.add((gn, RDF.type, GEO.Geometry))
        g.add((gn, GEO.asWKT, Literal(geom.wkt, datatype=WKT)))
        c[r["iso2"]] = k
        shapes[r["iso2"]] = geom
    save(g, "vocab/regions.ttl")
    return c, shapes


def taxonomy(mi):
    g = graph()
    s = scheme(g, "taxon", "Bird taxonomy", "The orders, families, genera and species of the dataset, from AviList v2025. Notations are AviList sequence numbers.",
               "https://doi.org/10.2173/avilist.v2025")
    g.add((s, DCTERMS.creator, Literal("AviList Core Team")))
    a = pd.read_csv("etl/sources/avilist.csv")
    tax, names = {}, {}
    cls = {"order": BIRD.Order, "family": BIRD.Family, "genus": BIRD.Genus, "species": BIRD.Species}
    for _, r in a.sort_values("Sequence").iterrows():
        rank = r.Taxon_rank
        parent = {"order": None, "family": tax.get(("order", r.Order)),
                  "genus": tax.get(("family", r.Family)),
                  "species": tax.get(("genus", r.Scientific_name.split()[0]))}[rank]
        label = r.Scientific_name if rank != "family" else r.Scientific_name
        c = concept(g, s, slug(r.Scientific_name), label, broader=parent, notation=int(r.Sequence),
                    extra_type=cls[rank])
        g.add((c, BIRD.rank, VOC[f"rank/{rank}"]))
        g.add((c, BIRD.scientificName, Literal(r.Scientific_name)))
        if rank == "family" and isinstance(r.Family_English_name, str):
            g.add((c, SKOS.altLabel, Literal(r.Family_English_name, lang="en")))
        if rank == "species":
            g.remove((c, SKOS.prefLabel, None))
            g.add((c, SKOS.prefLabel, Literal(r.English_name_AviList, lang="en")))
            g.add((c, SKOS.altLabel, Literal(r.Scientific_name)))
            if r.Scientific_name in mi:
                g.add((c, SKOS.altLabel, Literal(mi[r.Scientific_name], lang="mi")))
            for col, p in [("Range", BIRD.rangeText), ("Authority", BIRD.authority), ("Protonym", BIRD.protonym)]:
                if isinstance(r[col], str):
                    g.add((c, p, Literal(r[col])))
            if isinstance(r.Original_description_URL, str):
                g.add((c, RDFS.seeAlso, URIRef(r.Original_description_URL)))
            if isinstance(r.AvibaseID, str):
                g.add((c, DCTERMS.identifier, Literal(r.AvibaseID)))
            g.add((c, BIRD.extinct, Literal(isinstance(r.Extinct_or_possibly_extinct, str))))
            n = name_iri(r.Scientific_name)
            g.add((c, BIRD.acceptedName, n))
            names[r.Scientific_name] = c
        elif isinstance(r.Authority, str):
            g.add((c, BIRD.authority, Literal(r.Authority)))
        tax[(rank, r.Scientific_name)] = c
    save(g, "vocab/taxonomy.ttl")
    return tax, names, a


def full_taxonomy(subspecies=False):
    """Every order, family, genus and species of AviList v2025, with the same IRIs as taxonomy.ttl."""
    g = graph()
    s = VOC["taxon"]
    a = pd.read_csv("etl/.cache/avilist-all.csv", low_memory=False)
    ranks = ["order", "family", "genus", "species"] + (["subspecies"] if subspecies else [])
    a = a[a.Taxon_rank.isin(ranks)].sort_values("Sequence")
    seen = {}
    cls = {"order": BIRD.Order, "family": BIRD.Family, "genus": BIRD.Genus, "species": BIRD.Species}
    for r in a.itertuples():
        rank, name = r.Taxon_rank, r.Scientific_name
        if rank == "family":
            parent = seen.get(("order", r.Order))
        elif rank == "genus":
            parent = seen.get(("family", r.Family))
        elif rank == "species":
            parent = seen.get(("genus", name.split()[0]))
        elif rank == "subspecies":
            parent = seen.get(("species", " ".join(name.split()[:2])))
        else:
            parent = None
        c = URIRef(f"{s}/{slug(name)}")
        g.add((c, RDF.type, SKOS.Concept))
        if rank in cls:
            g.add((c, RDF.type, cls[rank]))
        g.add((c, SKOS.inScheme, s))
        g.add((c, SKOS.notation, Literal(str(int(r.Sequence)))))
        g.add((c, BIRD.rank, VOC[f"rank/{rank}"]))
        g.add((c, BIRD.scientificName, Literal(name)))
        if rank == "species" and isinstance(r.English_name_AviList, str):
            g.add((c, SKOS.prefLabel, Literal(r.English_name_AviList, lang="en")))
            g.add((c, SKOS.altLabel, Literal(name)))
        else:
            g.add((c, SKOS.prefLabel, Literal(name)))
        if rank == "family" and isinstance(r.Family_English_name, str):
            g.add((c, SKOS.altLabel, Literal(r.Family_English_name, lang="en")))
        if parent is None:
            g.add((s, SKOS.hasTopConcept, c))
            g.add((c, SKOS.topConceptOf, s))
        else:
            g.add((c, SKOS.broader, parent))
        seen[(rank, name)] = c
    save(g, "vocab/taxonomy-full.ttl" if not subspecies else "vocab/taxonomy-full-subspecies.ttl")


def name_iri(n):
    return ID[f"name/{slug(n)}"]


# ---------------------------------------------------------------- data

def species_data(v, tax, names, avilist):
    """Traits, red list status and accounts. Trophic niche, habitat and lifestyle are stated only where
    they differ from the nearest broader taxon, so the rule set Trait inheritance can restore them."""
    g = graph()
    av = pd.read_csv("etl/sources/avonet.csv").set_index("scientific_name")
    allav = pd.read_csv("etl/.cache/avonet-all.csv")
    allav["genus"] = allav.Species1.str.split().str[0]
    acc = pd.read_csv(AUTH / "accounts.csv").set_index("scientific_name")
    sp = avilist[avilist.Taxon_rank == "species"].set_index("Scientific_name")
    traits = [("Trophic.Niche", BIRD.trophicNiche, v["trophic"]), ("Habitat", BIRD.habitat, v["habitat"]),
              ("Primary.Lifestyle", BIRD.lifestyle, v["lifestyle"])]
    expected = graph()

    def mode(rows, col):
        vals = rows[col].dropna()
        return Counter(vals).most_common(1)[0][0] if len(vals) else None

    for col, prop, voc in traits:
        stated = {}
        for rank, key in [("order", "Order1"), ("family", "Family1"), ("genus", "genus")]:
            for (r, name), c in tax.items():
                if r != rank:
                    continue
                m = mode(allav[allav[key] == name], col)
                if m and (rank == "order" or m != effective(stated, tax, c)):
                    g.add((c, prop, voc[m]))
                    stated[c] = m
        for n, c in names.items():
            val = av.loc[n, col]
            if val != effective(stated, tax, c):
                g.add((c, prop, voc[val]))
            eff = {BIRD.trophicNiche: BIRD.effectiveTrophicNiche, BIRD.habitat: BIRD.effectiveHabitat,
                   BIRD.lifestyle: BIRD.effectiveLifestyle}[prop]
            expected.add((c, eff, voc[val]))

    for n, c in names.items():
        r = av.loc[n]
        g.add((c, BIRD.migration, v["migration"][int(r.Migration)]))
        for col, p in [("Mass", BIRD.bodyMass), ("Wing.Length", BIRD.wingLength), ("Beak.Length_Culmen", BIRD.beakLength),
                       ("Tail.Length", BIRD.tailLength), ("Hand-Wing.Index", BIRD.handWingIndex),
                       ("Range.Size", BIRD.rangeSize), ("Min.Latitude", BIRD.minLatitude), ("Max.Latitude", BIRD.maxLatitude)]:
            if pd.notna(r[col]):
                g.add((c, p, Literal(round(float(r[col]), 2), datatype=XSD.decimal)))
        if pd.notna(r["Centroid.Latitude"]):
            gn = URIRef(f"{c}/range-centroid")
            g.add((c, BIRD.rangeCentroid, gn))
            g.add((gn, RDF.type, GEO.Geometry))
            g.add((gn, GEO.asWKT, Literal(f"POINT({r['Centroid.Longitude']:.3f} {r['Centroid.Latitude']:.3f})", datatype=WKT)))
        cat = sp.loc[n, "IUCN_Red_List_Category"]
        if isinstance(cat, str):
            g.add((c, BIRD.redListCategory, v["redlist"][cat.split()[0]]))
        g.add((c, BIRD.account, Literal(acc.loc[n, "account"], lang="en")))
    save(g, "data/species.ttl")
    return expected


PARENT = {}


def effective(stated, tax, c):
    p = PARENT.get(c)
    while p is not None:
        if p in stated:
            return stated[p]
        p = PARENT.get(p)
    return None


def names_data(v, names, countries):
    g = graph()
    allnames = set(names)
    changes = list(csv.DictReader(open(AUTH / "name-changes.csv")))
    for ch in changes:
        allnames |= {ch["from_name"], ch["to_name"]}
    for n in sorted(allnames):
        g.add((name_iri(n), RDF.type, BIRD.Name))
        g.add((name_iri(n), BIRD.nameString, Literal(n)))
        g.add((name_iri(n), RDFS.label, Literal(n)))
    for i, ch in enumerate(changes, 1):
        x = ID[f"name-change/{i}"]
        g.add((x, RDF.type, BIRD.NameChange))
        g.add((x, BIRD.fromName, name_iri(ch["from_name"])))
        g.add((x, BIRD.toName, name_iri(ch["to_name"])))
        g.add((x, BIRD.changeType, v["change"][ch["change_type"]]))
        if ch["country"]:
            g.add((x, BIRD.changeRegion, countries[ch["country"]]))
        g.add((x, DCTERMS.source, Literal(ch["checklist"])))
        g.add((x, RDFS.comment, Literal(ch["note"], lang="en")))
    save(g, "data/names.ttl")
    return changes


def resolve(name, country, changes):
    seen = set()
    while name not in seen:
        seen.add(name)
        nxt = [c["to_name"] for c in changes if c["from_name"] == name and c["country"] in ("", country)]
        if not nxt:
            return name
        name = nxt[0]
    return name


def occurrences(names, countries, sites, changes):
    g = graph()
    occ = pd.read_csv(SRC / "gbif-occurrences.csv")
    occ = occ[occ.country.isin(countries) & (occ.event_date.str.len() == 10)]
    occ = occ.drop_duplicates("gbif_id")
    dropped = Counter()
    n = 0
    for _, r in occ.iterrows():
        queried = r.scientific_name
        true = resolve(queried, r.country, changes)
        if true not in names:
            dropped[(queried, r.country)] += 1
            continue
        o = ID[f"occurrence/{r.gbif_id}"]
        g.add((o, RDF.type, BIRD.Occurrence))
        g.add((o, BIRD.species, names[true]))
        ident = queried
        if queried == true:
            olds = [c["from_name"] for c in changes if c["to_name"] == true and c["country"] in ("", r.country)]
            if olds and r.gbif_id % 3 == 0:
                ident = olds[r.gbif_id % len(olds)]
        if ident != true:
            g.add((o, BIRD.identifiedAs, name_iri(ident)))
        g.add((o, BIRD.country, countries[r.country]))
        g.add((o, DWC.eventDate, Literal(r.event_date, datatype=XSD.date)))
        g.add((o, BIRD.month, Literal(int(r.month))))
        g.add((o, DWC.year, Literal(int(r.year))))
        g.add((o, DWC.basisOfRecord, Literal(r.basis_of_record)))
        if pd.notna(r.individual_count):
            g.add((o, DWC.individualCount, Literal(int(r.individual_count))))
        if pd.notna(r.uncertainty_m):
            g.add((o, DWC.coordinateUncertaintyInMeters, Literal(float(r.uncertainty_m), datatype=XSD.decimal)))
        gn = URIRef(f"{o}/geometry")
        g.add((o, GEO.hasGeometry, gn))
        g.add((gn, RDF.type, GEO.Geometry))
        g.add((gn, GEO.asWKT, Literal(f"POINT({r.lon} {r.lat})", datatype=WKT)))
        pt = Point(r.lon, r.lat)
        for s, (iri, poly) in sites.items():
            if poly.contains(pt):
                g.add((o, BIRD.site, iri))
        g.add((o, DCTERMS.source, URIRef(f"https://www.gbif.org/occurrence/{r.gbif_id}")))
        g.add((o, DCTERMS.isPartOf, URIRef(f"https://www.gbif.org/dataset/{r.dataset_key}")))
        g.add((o, DCTERMS.license, URIRef(r.license.replace("http://", "https://").removesuffix("legalcode"))))
        n += 1
    print("occurrences dropped (species not in list):", dict(dropped))
    save(g, "data/occurrences.ttl")
    return occ


def monthly(names, countries, changes):
    g = graph()
    m = pd.read_csv(SRC / "gbif-monthly-counts.csv")
    m = m[m.country.isin(countries)].copy()
    m["true"] = [resolve(n, c, changes) for n, c in zip(m.scientific_name, m.country)]
    # A record can match the old and the new name. Take the larger count, not the sum.
    m = m[m["true"].isin(names)].groupby(["true", "country", "month"], as_index=False)["count"].max()
    rec = defaultdict(set)
    for _, r in m.iterrows():
        true = r["true"]
        x = ID[f"monthly-count/{slug(true)}/{r.country.lower()}/{int(r.month)}"]
        g.add((x, RDF.type, BIRD.MonthlyCount))
        g.add((x, BIRD.species, names[true]))
        g.add((x, BIRD.country, countries[r.country]))
        g.add((x, BIRD.month, Literal(int(r.month))))
        g.add((x, BIRD.recordCount, Literal(int(r["count"]))))
        rec[true].add(r.country)
    for sp, cs in rec.items():
        for c in cs:
            g.add((names[sp], BIRD.recordedIn, countries[c]))
    save(g, "data/monthly-counts.ttl")


def sites_data(v, countries):
    g = graph()
    out = {}
    for r in csv.DictReader(open(AUTH / "sites.csv")):
        s = ID[f"site/{r['slug']}"]
        lat, lon, hl, ho = (float(r[k]) for k in ("lat", "lon", "half_lat", "half_lon"))
        poly = box(lon - ho, lat - hl, lon + ho, lat + hl)
        g.add((s, RDF.type, BIRD.Site))
        g.add((s, RDF.type, GEO.Feature))
        g.add((s, RDFS.label, Literal(r["name"], lang="en")))
        g.add((s, DCTERMS.description, Literal(r["description"], lang="en")))
        g.add((s, BIRD.country, countries[r["country"]]))
        g.add((s, BIRD.siteType, v["site_type"][r["site_type"]]))
        g.add((s, BIRD.latitude, Literal(lat, datatype=XSD.decimal)))
        g.add((s, BIRD.longitude, Literal(lon, datatype=XSD.decimal)))
        gn = URIRef(f"{s}/geometry")
        g.add((s, GEO.hasGeometry, gn))
        g.add((gn, RDF.type, GEO.Geometry))
        g.add((gn, GEO.asWKT, Literal(poly.wkt, datatype=WKT)))
        g.add((gn, RDFS.comment, Literal("An approximate rectangle around the site.", lang="en")))
        out[r["slug"]] = (s, poly)
    save(g, "data/sites.ttl")
    return out


def bands(names, sites):
    g = graph()
    for r in csv.DictReader(open(AUTH / "banded-birds.csv")):
        b = ID[f"bird/{r['band'].lower()}"]
        g.add((b, RDF.type, BIRD.BandedBird))
        g.add((b, BIRD.bandNumber, Literal(r["band"])))
        g.add((b, BIRD.species, names[r["species"]]))
        g.add((b, BIRD.bandedAt, sites[r["site"]][0]))
        g.add((b, BIRD.site, sites[r["site"]][0]))
        g.add((b, BIRD.bandedOn, Literal(r["date"], datatype=XSD.date)))
        g.add((b, BIRD.date, Literal(r["date"], datatype=XSD.date)))
        g.add((b, RDFS.comment, Literal(r["colour_combination"])))
    prev = {}
    for r in csv.DictReader(open(AUTH / "resightings.csv")):
        b = ID[f"bird/{r['band'].lower()}"]
        x = ID[f"resighting/{r['band'].lower()}/{r['seq']}"]
        g.add((x, RDF.type, BIRD.Resighting))
        g.add((x, BIRD.bird, b))
        g.add((x, BIRD.site, sites[r["site"]][0]))
        g.add((x, BIRD.date, Literal(r["date"], datatype=XSD.date)))
        g.add((x, BIRD.previous, prev.get(r["band"], b)))
        g.add((x, BIRD.note, Literal(r["note"], lang="en")))
        prev[r["band"]] = x
    save(g, "data/banded-birds.ttl")


def food_web(v, names):
    g = graph()
    for r in csv.DictReader(open(AUTH / "food-web.csv")):
        food = names.get(r["food"]) or v["food"][r["food"]]
        g.add((names[r["eater"]], BIRD.eats, food))
    save(g, "data/food-web.ttl")


def main():
    v = small_vocabs()
    countries, _ = regions()
    mi = dict(csv.reader(open(AUTH / "vernacular-mi.csv")))
    tax, names, avilist = taxonomy(mi)
    tg = Graph().parse(OUT / "vocab/taxonomy.ttl")
    for c, p in tg.subject_objects(SKOS.broader):
        PARENT[c] = p
    expected = species_data(v, tax, names, avilist)
    save(expected, "rules/expected/trait-inheritance-species.ttl")
    changes = names_data(v, names, countries)
    sites = sites_data(v, countries)
    occurrences(names, countries, sites, changes)
    monthly(names, countries, changes)
    bands(names, sites)
    food_web(v, names)
    if os.environ.get("BIRDS_FULL"):
        full_taxonomy()


if __name__ == "__main__":
    main()
