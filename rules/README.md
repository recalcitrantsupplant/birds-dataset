# Rule sets

Each rule set is SRL (SHACL 1.2 rules). Each one needs a feature that one
SPARQL query does not have: recursion over facts that a rule derived, or a
chain of rules where a later rule reads an earlier rule's output.
`rules/expected/<rule set>.nt` holds the triples it infers from the files in
`etl/scripts/run_rules.sh`. The script also checks that `trait-inheritance`
reproduces the AVONET value of each species.

| Rule set | Reads | Infers | SRL features |
| --- | --- | --- | --- |
| `trait-inheritance` | taxonomy, species | `bird:effectiveTrophicNiche`, `bird:effectiveHabitat`, `bird:effectiveLifestyle` for every taxon: its own value, or the value of its nearest broader taxon that states one | Recursion up `skos:broader`, with `NOT` so that a stated value overrides an inherited one |
| `name-resolution` | regions, taxonomy, names, occurrences | `bird:resolvesTo`: the current species of each occurrence, through every name change that applies in its country | Recursion over a chain of changes, a country condition at each step, `NOT` to find the end of the chain |
| `food-web` | food resources, taxonomy, food web | `bird:dependsOn` (everything a species depends on, directly or through its prey), apex predators, mixed feeders, the count of basic food resources, `bird:InFeedingCycle`, `bird:trophicLevel` | Recursion through a food web with cycles (kookaburra and magpie take each other's nestlings), `NOT`, `GROUP` with `COUNT(DISTINCT)`. A step table carries `bird:trophicLevel` through the recursion, then `GROUP` with `MAX` |
| `flyways` | sites, banded birds | `bird:flywayLink` between consecutive sites of a banded bird, `bird:reaches` over those links, `bird:connectedTo` between countries, `bird:usesSite` for each species, `bird:hopNumber` of each resighting, `bird:firstReturnHop` and `bird:northSouthKm` of each banded bird | Recursion over links that a rule derived. A step table carries the hop number, then `GROUP` with `MIN`, and `GROUP` with `SUM` over `SET` |
| `seasonal-status` | seasons, regions, monthly counts | The season of each monthly count, by hemisphere. Record totals per season. The seasons in which each species is present in each country. Its status: resident, summer visitor, winter visitor, passage migrant | Four strata: `SET` with `IRI()`, `GROUP` with `SUM` and `MAX`, then `NOT` |

`GROUP` needs the `ruleAggregates` feature flag of sqlib.

## Numbers through recursion

A rule set can have many `SET` and `GROUP` rules. sqlib runs each such rule
once, after the rules it depends on. It refuses a `SET` or `GROUP` rule that
is part of a recursive cycle, because the rule would then make a new value on
each pass and the run would not end.

`food-web` and `flyways` carry a count through recursion with a step table in
`DATA`: `bird:step1 bird:depth 1 ; bird:nextStep bird:step2`, and so on. The
recursive rule moves to the next step node and creates no value. A later
`GROUP` rule reads `bird:depth` from the step nodes and takes `MAX`, `MIN` or
`SUM`. The table sets the largest count: 6 trophic levels and 8 hops. A chain
that is longer stops at the last step.

The trophic-level rule skips prey that depends on the predator (`NOT`), so
the kookaburra and magpie cycle does not climb to the top step.

Results on the checked-in data:

| Rule set | Passes | Triples inferred | Check |
| --- | --- | --- | --- |
| `trait-inheritance` | 4 | 819 | The 333 species values match AVONET exactly |
| `name-resolution` | 4 | 4,445 | All 2,081 occurrences resolve to one species, the species the build filed them under |
| `food-web` | 6 | 557 | 7 apex predators, 8 mixed feeders. Trophic level 3 for 4 species (peregrine falcon, New Zealand falcon, wedge-tailed eagle, African fish eagle), 2 for 87. Kookaburra and magpie are in a feeding cycle |
| `flyways` | 7 | 306 | 36 country connections. 40 resightings carry a hop number. Bar-tailed godwit NZ-B-40101 covers 39,013 km north to south and is back at Firth of Thames at hop 3. The sandhill crane joins the American and East Asian–Australasian links through the Yukon-Kuskokwim Delta |
| `seasonal-status` | 8 | 10,439 | Bar-tailed godwit: summer visitor in New Zealand. Wrybill: resident in New Zealand. Barn swallow: summer visitor in Britain |
