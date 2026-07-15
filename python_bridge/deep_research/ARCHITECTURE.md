# Hierarchical RAG Decision

The index uses 320-word leaves with a 50-word overlap (approximately 250-400
tokens for ordinary web prose), a Tier 1 extractive source-page summary, and a
Tier 2 extractive stage summary. RAPTOR validates recursively summarized
multi-granularity retrieval; this implementation uses source pages as the
stable parent instead of clustering a short-lived, heterogeneous web corpus.

Retrieval embeds the query, ranks only Tier 1 nodes in the requested stage,
then ranks Tier 0 leaves from the selected five pages. This is the practical
parent-child/small-to-big pattern: source-level relevance narrows the leaf
search while leaf vectors retain precise matching.

At the 25-fetch safety limit, a stage normally contains about 125-300 leaves
(five to twelve chunks per page). Even 15 stages are only roughly 1,875-4,500
leaves. A full cosine pass over 300 vectors at query time is negligible, and
SQLite stores text/metadata/vectors reliably in Termux. sqlite-vec would add a
native Android extension and ABI deployment concern without a material benefit
at this scale, so it is intentionally not a dependency.
