"""Validate data/*.ttl and vocab/*.ttl against ontology/shapes.ttl. Exits 1 on a violation."""
import glob, sys

from pyshacl import validate
from rdflib import Graph

g = Graph()
for f in sorted(glob.glob("data/*.ttl") + glob.glob("data/*.nt") + glob.glob("vocab/*.ttl")):
    g.parse(f)
ont = Graph().parse("ontology/birds.ttl")
ok, _, text = validate(g, shacl_graph=Graph().parse("ontology/shapes.ttl"), ont_graph=ont, inference="rdfs")
print(f"{len(g)} triples: {'conforms' if ok else 'does not conform'}")
if not ok:
    print(text)
    sys.exit(1)
