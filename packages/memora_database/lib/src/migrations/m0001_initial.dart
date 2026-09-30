import 'package:sqlite3/sqlite3.dart';

import 'migration.dart';

/// The first schema. See docs/architecture.md, section 6.1.
class M0001Initial extends Migration {
  const M0001Initial();

  @override
  int get version => 1;

  @override
  void up(Database db) {
    for (final statement in _statements) {
      db.execute(statement);
    }
  }
}

const _statements = <String>[
  '''
CREATE TABLE memories (
  seq INTEGER PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  image_path TEXT NOT NULL,
  thumbnail_path TEXT,
  source TEXT NOT NULL,
  sha256 TEXT NOT NULL UNIQUE,
  mime_type TEXT NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  byte_size INTEGER NOT NULL,
  taken_at INTEGER NOT NULL,
  added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN (
    'captured', 'processing', 'ready', 'failed', 'reprocessing', 'deleted'
  )),
  summary TEXT,
  visual_description TEXT,
  extracted_text TEXT,
  category TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  lease_until INTEGER,
  next_attempt_at INTEGER,
  failure_reason TEXT,
  processed_at INTEGER,
  last_viewed_at INTEGER
)''',
  'CREATE INDEX memories_status_taken_at ON memories (status, taken_at)',
  // The queue screen's tail of recently finished memories.
  'CREATE INDEX memories_status_processed_at '
      'ON memories (status, processed_at)',
  'CREATE INDEX memories_taken_at ON memories (taken_at)',
  'CREATE INDEX memories_category ON memories (category)',
  '''
CREATE TABLE entities (
  id INTEGER PRIMARY KEY,
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  normalized_value TEXT NOT NULL
)''',
  'CREATE INDEX entities_memory_id ON entities (memory_id)',
  'CREATE INDEX entities_normalized_value ON entities (normalized_value)',
  '''
CREATE TABLE attributes (
  id INTEGER PRIMARY KEY,
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  value TEXT NOT NULL,
  value_num REAL,
  value_date TEXT,
  currency TEXT,
  label TEXT
)''',
  'CREATE INDEX attributes_memory_id ON attributes (memory_id)',
  'CREATE INDEX attributes_type_value_num ON attributes (type, value_num)',
  'CREATE INDEX attributes_type_value_date ON attributes (type, value_date)',
  '''
CREATE TABLE keywords (
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  keyword TEXT NOT NULL,
  PRIMARY KEY (memory_id, keyword)
)''',
  'CREATE INDEX keywords_keyword ON keywords (keyword)',
  '''
CREATE TABLE embeddings (
  id INTEGER PRIMARY KEY,
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  vector BLOB NOT NULL,
  model_id TEXT NOT NULL,
  model_version TEXT NOT NULL,
  dimensions INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (memory_id, model_id, model_version)
)''',
  'CREATE INDEX embeddings_model ON embeddings (model_id, model_version)',
  // The tokenizer categories matter for Indic scripts. Without Mc and Mn the
  // default splits a word at every vowel sign, so बिजली goes into the index
  // as ब, जल and ल. remove_diacritics 2 still folds Latin accents, so Café is
  // found by cafe.
  '''
CREATE VIRTUAL TABLE memories_fts USING fts5(
  summary,
  extracted_text,
  visual_description,
  keywords,
  entities,
  tokenize = "unicode61 remove_diacritics 2 categories 'L* N* Co Mc Mn'"
)''',
  '''
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''',
  '''
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL
    REFERENCES conversations (id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  presentation TEXT,
  tool_trace TEXT,
  provider TEXT,
  model TEXT,
  created_at INTEGER NOT NULL
)''',
  'CREATE INDEX messages_conversation_created_at '
      'ON messages (conversation_id, created_at)',
  '''
CREATE TABLE message_references (
  message_id TEXT NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  relevance_score REAL,
  position INTEGER NOT NULL,
  PRIMARY KEY (message_id, memory_id)
)''',
  'CREATE INDEX message_references_memory_id '
      'ON message_references (memory_id)',
  // message_id has no foreign key: tools save result sets during a turn,
  // before the assistant message that owns them is written.
  '''
CREATE TABLE result_sets (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL
    REFERENCES conversations (id) ON DELETE CASCADE,
  message_id TEXT,
  description TEXT NOT NULL,
  memory_ids TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''',
  'CREATE INDEX result_sets_conversation_created_at '
      'ON result_sets (conversation_id, created_at)',
  '''
CREATE TABLE processing_metadata (
  id INTEGER PRIMARY KEY,
  memory_id TEXT NOT NULL REFERENCES memories (id) ON DELETE CASCADE,
  capability TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  version TEXT,
  status TEXT NOT NULL,
  latency_ms INTEGER,
  error TEXT,
  created_at INTEGER NOT NULL
)''',
  'CREATE INDEX processing_metadata_memory_created_at '
      'ON processing_metadata (memory_id, created_at)',
  '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
];
