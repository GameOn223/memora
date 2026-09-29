/// Domain model, ports and services behind Memora.
///
/// Nothing in this package knows about Flutter, Android, SQLite or any AI
/// vendor. See docs/architecture.md for how the pieces fit together.
library;

export 'src/ai/capabilities.dart';
export 'src/ai/errors.dart';
export 'src/ai/local_only_policy.dart';
export 'src/ai/prompts.dart';
export 'src/ai/provider.dart';
export 'src/ai/registry.dart';
export 'src/ai/router.dart';
export 'src/ai/settings.dart';
export 'src/chat/agent_chat_engine.dart';
export 'src/chat/aggregation.dart';
export 'src/chat/answer_verifier.dart';
export 'src/chat/citations.dart';
export 'src/chat/deterministic_answerer.dart';
export 'src/chat/presentation_builder.dart';
export 'src/chat/query_labels.dart';
export 'src/chat/query_parser.dart';
export 'src/chat/system_prompt.dart';
export 'src/chat/tools/result_set_tools.dart';
export 'src/chat/tools/search_tools.dart';
export 'src/chat/tools/tool.dart';
export 'src/chat/tools/tool_registry.dart';
export 'src/embedding/wordpiece_tokenizer.dart';
export 'src/extraction/rule_based_extractor.dart';
export 'src/model/conversation.dart';
export 'src/model/details.dart';
export 'src/model/memory.dart';
export 'src/model/processing.dart';
export 'src/model/retrieval.dart';
export 'src/model/understanding.dart';
export 'src/ports/embedding_model.dart';
export 'src/ports/platform.dart';
export 'src/ports/stores.dart';
export 'src/processing/default_ingestor.dart';
export 'src/processing/default_pipeline.dart';
export 'src/processing/embedding_text.dart';
export 'src/processing/fact_normalizer.dart';
export 'src/processing/queue_policy_repository.dart';
export 'src/retrieval/default_retrieval_engine.dart';
export 'src/retrieval/fusion_reranker.dart';
export 'src/retrieval/rank_fusion.dart';
export 'src/services/contracts.dart';
export 'src/text/amounts.dart';
export 'src/text/dates.dart';
export 'src/text/money_format.dart';
export 'src/text/normalize.dart';
export 'src/util/json.dart' show normalizeKey;
