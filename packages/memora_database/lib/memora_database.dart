/// SQLite storage for Memora.
///
/// Implements the storage ports from `memora_core` with FTS5 full-text search,
/// brute-force vector search and numbered migrations. See
/// docs/architecture.md, section 6.
library;

export 'src/memora_database.dart' show MemoraDatabase;
export 'src/sqlite_memory_store.dart' show SqliteMemoryStore;
export 'src/sqlite_queue_store.dart' show SqliteQueueStore;
export 'src/sqlite_search_store.dart' show SqliteSearchStore;
export 'src/sqlite_vector_store.dart' show SqliteVectorStore;
