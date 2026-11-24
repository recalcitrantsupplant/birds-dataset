# Rule sets

Each rule set is SRL (SHACL 1.2 rules). Each one needs a feature that one
SPARQL query does not have: recursion over facts that a rule derived, or a
chain of rules where a later rule reads an earlier rule's output.
`rules/expected/<rule set>.nt` holds the triples it infers from the files in
`etl/scripts/run_rules.sh`.

| Rule set | Reads | Infers | SRL features |
| --- | --- | --- | --- |
| `trait-inheritance` | taxonomy, species | `bird:effectiveTrophicNiche`, `bird:effectiveHabitat`, `bird:effectiveLifestyle` for every taxon: its own value, or the value of its nearest broader taxon that states one | Recursion up `skos:broader`, with `NOT` so that a stated value overrides an inherited one |
| `name-resolution` | regions, taxonomy, names, occurrences | `bird:resolvesTo`: the current species of each occurrence, through every name change that applies in its country | Recursion over a chain of changes, a country condition at each step, `NOT` to find the end of the chain |
| `food-web` | food resources, taxonomy, food web | `bird:dependsOn` (everything a species depends on, directly or through its prey), apex predators, mixed feeders, the count of basic food resources | Recursion through a food web with cycles (kookaburra and magpie take each other's nestlings), `NOT`, `GROUP` with `COUNT(DISTINCT)` |
| `flyways` | sites, banded birds | `bird:flywayLink` between consecutive sites of a banded bird, `bird:reaches` over those links, `bird:connectedTo` between countries, `bird:usesSite` for each species | Recursion over links that a rule derived |
| `seasonal-status` | seasons, regions, monthly counts | The season of each monthly count, by hemisphere. Record totals per season. The seasons in which each species is present in each country. Its status: resident, summer visitor, winter visitor, passage migrant | Four strata: `SET` with `IRI()`, `GROUP` with `SUM` and `MAX`, then `NOT` |

`GROUP` needs the `ruleAggregates` feature flag of sqlib.

Results on the checked-in data:

| Rule set | Passes | Triples inferred | Check |
| --- | --- | --- | --- |
| `trait-inheritance` | 4 | 819 | The 333 species values match AVONET exactly |
| `name-resolution` | 4 | 4,445 | All 2,081 occurrences resolve to one species, the species the build filed them under |
| `food-web` | 4 | 360 | 7 apex predators, 8 mixed feeders |
| `flyways` | 5 | 182 | 36 country connections. The sandhill crane joins the American and East Asian–Australasian links through the Yukon-Kuskokwim Delta |
| `seasonal-status` | 8 | 10,439 | Bar-tailed godwit: summer visitor in New Zealand. Wrybill: resident in New Zealand. Barn swallow: summer visitor in Britain |
