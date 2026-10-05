import 'package:sqlite3/sqlite3.dart';

import 'migration.dart';

/// Lets a conversation be pinned to the top of the list.
///
/// `ALTER TABLE ... ADD COLUMN` with a constant default fills existing rows
/// without rewriting the table, so every conversation from version 1 comes
/// back unpinned.
class M0002PinnedConversations extends Migration {
  const M0002PinnedConversations();

  @override
  int get version => 2;

  @override
  void up(Database db) {
    db
      ..execute(
        'ALTER TABLE conversations '
        'ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
      )
      // The list reads pinned conversations first, then the rest, each group
      // newest updated first. One index covers both groups.
      ..execute(
        'CREATE INDEX conversations_pinned_updated_at '
        'ON conversations (pinned DESC, updated_at DESC)',
      );
  }
}
