# Triplet scoring — heuristic-1

The objective is one recognizable entity transformed by two influences. Conceptual distance alone is not a reason to reject a combination. The scorer estimates **input composability**, not actual visual quality.

## Roles and similarity

Each concept has fuzzy subject, feature, material, accessory, setting, atmosphere and emotion-symbol scores in [0,1]. Seven templates are evaluated over all six permutations. Assignment fit is the geometric mean of three suitability scores times the template prior. Object-role slots use objectness; character slots use character-likeness. Ties are resolved by stable template/permutation order. Selected assignment order is persisted separately from unordered identity.

Template priors, in source order: 1.00, 0.95, 0.95, 0.85, 0.90, 0.85, 0.80. The object in subject-object-atmosphere uses objectness for scoring; its current prompt label is accessory, a known display simplification.

Local similarity tokenizes NFC-normalized lowercased names and CLDR keywords, removes seven English stopwords, and maps a small explicit alias dictionary (for example lunar→moon, flame→fire). `s = clamp(0.65 * Jaccard(tokens) + 0.10 * sameGroup + 0.25 * sameSubgroup)`. Identity scores 1. Tokens are cached per selection. It is a simple deterministic relation heuristic, not an embedding model.

## Components

All clamp operations restrict to [0,1]. Let `m` be mean pair similarity, `x` maximum pair similarity, `v_i` each visual vector, and ordered concepts refer to the best assignment.

- Anchor A = max(0.45·subject + 0.35·objectness + 0.20·salience).
- Role fit R = maximum assignment fit.
- Modifier transformability M = mean(transformability of assignment slots 1 and 2).
- Competition K = min(subject·(1−transformability)) across the triple.
- Clutter C = clamp((sum complexity + 0.5·sum scene-likeness)/4.5).
- Single-entity potential E = clamp(0.5·max(primary subject, primary objectness) + 0.5·M − 0.15·K).
- Visual compatibility V = clamp(0.35·A + 0.40·M + 0.25·(1−C)).
- Goldilocks novelty G = exp(−(m−0.30)²/(2·0.20²)).
- Recent reuse U = fraction of triple IDs in recent accepted generations.
- Novelty N = (1−pressure) + pressure·G·(1−U). Pressure zero disables the novelty penalty. A separate hard recent exclusion still applies to new replacements when enabled.
- Coherence H = clamp(0.5·R + 0.5·min(1,m/0.30)).
- Redundancy D = clamp((x−0.50)/0.50).

`Q = clamp((0.20R + 0.18V + 0.15E + 0.15A + 0.12N + 0.08H − 0.12D − 0.12C − 0.08K)/0.88)`.

Weights and formulas are versioned together as heuristic-1. Thresholds/batch limits are centralized in TripletScoringConfiguration; coefficients are not user-editable. VisualFeatureVector means physical depictability, emoji-scale salience, bounded-object potential, character/scene likeness, abstraction, intrinsic complexity and suitability for becoming a modifier. All are script-derived estimates.

## Hard rules and regimes

Every regime requires three distinct validated catalog IDs, active exclusions/groups/ZWJ settings, pins, exact mutation count, and selected repeat policy. Strict additionally requires default eligibility, anchor ≥0.70, role fit ≥0.50, total Q ≥0.70, complexity sum ≤2.1, and rejects three abstract/nonconcrete symbols, three full low-transformability subjects, three humans, three faces, and at least two pair similarities ≥0.88. These quality rules do not get overridden by personal preference. Exploratory keeps the universal constraints with Q≥0.45. Wild has no Q threshold or model veto.

## Construction and selection

Sample a role template with its prior. For each mutable slot, weight eligible candidates by squared role suitability × salience in Strict, and uniform base weight otherwise; apply the documented semantic mutation multiplier. Cached cumulative distributions give O(log N) draws. Conditional rejection probability is the product of max(0.01,1−similarity to selected concepts); Wild uses probability 1. Reject duplicates. Each slot has at most 32 draws.

Keep up to 64 distinct qualifying candidates from at most 384 attempts. Exhaustion reports an error; hard constraints and the threshold are not silently weakened. Rank by deterministic Q, or 0.85Q + 0.15 preference when enough labels exist. With probability 0.10 sample uniformly from the 12 highest-novelty qualifying candidates; otherwise softmax-sample the 12 highest-ranked candidates at temperature 0.20. Subtract the maximum before exponentiation. Ties break by rank. Every random choice consumes SplitMix64.

## Calibration and limitations

`triplet-simulation 100000` evaluates **uniform distinct proposals from the strict-eligible aesthetic-filtered corpus**, reporting acceptance/score distribution, role/group mix, mean similarity, duplicate proposal rate, rejection reasons and examples. It also benchmarks 10 actual constructive selections. Uniform-proposal acceptance must not be mistaken for constructive-selector success rate. See `VERIFICATION.md` for the actual final run.

The threshold is retained only after the five specified strong fixtures pass and poor fixtures reject. Offline statistics do not prove aesthetic quality or native image success. Language heuristics, coarse lexical tags, popularity imbalance, and independent-template priors require user/device study. No exact count of valid Strict triples is claimed. The combinatorial space, deterministic admissibility and contextual ranking remain distinct.
