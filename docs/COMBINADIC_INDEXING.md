# Exact unordered triplet identity

Concept IDs must be zero-based, contiguous integers in a versioned catalog. Sort three distinct IDs to `a < b < c`. Define `rank = C(a,1) + C(b,2) + C(c,3)`. The public initializer rejects negative or duplicate IDs and checks overflow.

This is the colexicographic combinatorial number system. All triples with maximum element less than `c` occupy the first `C(c,3)` ranks. Within the block ending in `c`, all pairs whose maximum is below `b` occupy `C(b,2)` positions; the remaining offset is `a`. The blocks are contiguous, so N concepts occupy exactly `0...C(N,3)-1`.

Unranking greedily chooses the largest c with `C(c,3) <= rank`, subtracts that term, then the largest b below c with `C(b,2) <= remainder`, followed by a. Binary search gives O(log N) work for each of the three terms. The input rank is checked against the catalog's combination count.

Binomial coefficients use integer arithmetic only. Denominator factors are cancelled with gcd before checked UInt64 multiplication; rank additions are checked. Unsupported k > 3 and arithmetic overflow throw errors. No floating-point binomial approximations or concatenated emoji identities are used.

Tests exhaustively enumerate every triple for each N from 3 through 30, checking uniqueness, minimum/maximum rank, C(N,3) count, ranking/unranking round trips, and all six input permutations. Additional tests cover invalid input and UInt64 overflow. IDs from different catalog versions are not comparable without migration.
