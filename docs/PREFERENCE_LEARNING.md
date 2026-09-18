# Local preference learning — logistic-1

Explicit ratings: poor=-1, neutral=0, good=1, favorite=2. Poor maps to target 0; good/favorite map to 1; neutral is unlabeled. Behavior signals are stored separately and **not used as training labels**. Changing a rating rebuilds the model from current unique node labels, so repeated taps do not multiply that node's weight.

Feature schema `quality11-template7-v1`: anchor, role fit, visual compatibility, single-entity potential, novelty, coherence, redundancy, clutter, competition, mean similarity, maximum similarity, then seven template one-hot indicators. There are 18 features; raw emoji text is never a statistical model input. Group-pair features and post-generation proxies are not yet implemented.

Start coefficients w=0 and bias b=0. After at least 12 informative unique-node labels, traverse node UUIDs in sorted order for 20 passes. For each label `(x,y)`, compute stable sigmoid p=σ(w·x+b), then `w_j ← w_j − 0.05((p−y)x_j + 0.02w_j)` and `b ← b − 0.05(p−y)`. This is regularized stochastic logistic optimization with deterministic ordering. Coefficients, schema, count, model version and update date are persisted in a separate SwiftData snapshot. Labels are retained for rebuilding.

Before 12 labels the ranking term is absent. Invalid/nonfinite vectors are excluded; coefficient/schema mismatches reset safely. Tests check gate behavior, positive/negative movement, finite regularized weights, reset and feature-version mismatch. There is no claim of calibrated probability or performance on real user ratings yet.

When active, preference contributes 15% of ranking after deterministic admission. It cannot restore a hard-rejected, excluded or repeated candidate. Exploration remains at 10%. No Foundation Models critic is currently implemented, so no missing critic value is imputed.

Reset clears local ratings, behavioral records and the model after confirmation. Run deletion removes its training examples and rebuilds coefficients. Metadata export includes model parameters and separate feedback records, never native glyph binaries. This is local file export initiated by the user, not automatic transmission. UI preference status/export and model updates still require device validation.
