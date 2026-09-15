/// Domain model, ports and services behind Memora.
///
/// Nothing in this package knows about Flutter, Android, SQLite or any AI
/// vendor. See docs/architecture.md for how the pieces fit together.
library;

export 'src/ai/capabilities.dart';
export 'src/ai/errors.dart';
export 'src/ai/local_only_policy.dart';
export 'src/ai/provider.dart';
export 'src/ai/registry.dart';
export 'src/ai/router.dart';
export 'src/ai/settings.dart';
export 'src/model/conversation.dart';
export 'src/model/details.dart';
export 'src/model/memory.dart';
export 'src/model/processing.dart';
export 'src/model/retrieval.dart';
export 'src/model/understanding.dart';
export 'src/ports/embedding_model.dart';
export 'src/ports/platform.dart';
export 'src/ports/stores.dart';
export 'src/services/contracts.dart';
export 'src/util/json.dart' show normalizeKey;
