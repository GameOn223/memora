import 'package:meta/meta.dart';

import '../model/conversation.dart';
import '../model/memory.dart';
import '../model/processing.dart';
import '../model/retrieval.dart';
import '../model/understanding.dart';
import '../ports/platform.dart';

/// A file already copied into app storage by the platform layer.
@immutable
class ImportedFile {
  const ImportedFile({
    required this.imagePath,
    required this.sha256,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.takenAt,
  });

  /// Relative to the app files directory, for example `originals/<uuid>.png`.
  final String imagePath;
  final String sha256;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;
  final DateTime takenAt;
}

@immutable
class IngestReport {
  const IngestReport({
    required this.addedIds,
    required this.duplicateCount,
    this.duplicatePaths = const [],
  });

  final List<String> addedIds;

  /// Images skipped because they were already in Memora.
  final int duplicateCount;

  /// The copies those skipped images were made into, relative to the app
  /// files directory. Nothing points at them, so the caller can delete them.
  /// The ingestor tries as well.
  final List<String> duplicatePaths;
}

/// Turns copied files into memory rows and thumbnails.
abstract interface class MemoryIngestor {
  Future<IngestReport> ingest(List<ImportedFile> files, MemorySource source);

  /// Creates any thumbnails that are still missing. Safe to call repeatedly.
  Future<int> backfillThumbnails();
}

/// What one call to [ProcessingPipeline.processNext] did.
sealed class ProcessOutcome {
  const ProcessOutcome();
}

final class Processed extends ProcessOutcome {
  const Processed(this.memoryId, this.status);

  final String memoryId;

  /// `ready`, `captured` (will retry) or `failed`.
  final ProcessingStatus status;
}

final class QueueEmpty extends ProcessOutcome {
  const QueueEmpty();
}

final class QueueBlocked extends ProcessOutcome {
  const QueueBlocked(this.block);

  final QueueBlock block;
}

@immutable
class QueueRunReport {
  const QueueRunReport({
    required this.processed,
    required this.remaining,
    this.block,
    this.nextAttemptAt,
  });

  final int processed;

  /// True when memories are still waiting, including ones that are waiting
  /// out a retry backoff. The scheduler re-enqueues itself when this is set.
  final bool remaining;
  final QueueBlock? block;

  /// The earliest retry this run scheduled, so the scheduler can wait that
  /// long instead of starting again right away. Null when nothing was
  /// deferred.
  final DateTime? nextAttemptAt;
}

/// Runs understanding for queued memories. See docs/architecture.md, section 5.
abstract interface class ProcessingPipeline {
  Future<ProcessOutcome> processNext();

  /// Processes items one at a time until the queue is empty, the policy says
  /// stop, or [budget] runs out. Never stops in the middle of an item.
  Future<QueueRunReport> runQueue({
    required Duration budget,
    bool processNow = false,
  });

  /// Rebuilds vectors for memories missing one for the active embedding model.
  Future<int> reindexEmbeddings({required Duration budget});

  /// The reason understanding cannot run right now, or null when it can.
  ///
  /// Covers a missing vision provider, one refused by local-only mode, a
  /// configuration problem such as a missing key, a provider with no service
  /// for the model it is set to, and a rate limit the queue is waiting out.
  /// Cheap enough to call before adding images: it reads settings and
  /// resolves capabilities, makes no provider call and claims no memory.
  Future<QueueBlock?> currentBlock();
}

@immutable
class RetrievalResult {
  const RetrievalResult({
    required this.hits,
    required this.strategiesUsed,
    this.textMatched = true,
  });

  final List<RankedMemory> hits;

  /// Strategies that actually ran. Semantic is skipped without embeddings.
  final Set<RetrievalStrategy> strategiesUsed;

  /// False when the query had words, none of them matched anything inside
  /// the filters, and the hits are the filtered memories instead. The answer
  /// should say so rather than pretending the words matched.
  final bool textMatched;
}

/// Hybrid search. See docs/architecture.md, section 8.
abstract interface class RetrievalEngine {
  Future<RetrievalResult> search(RetrievalQuery query);
}

/// Extracts a basic understanding from OCR output without a vision model.
/// Used by the on-device vision provider.
abstract interface class OcrUnderstandingExtractor {
  MemoryUnderstanding extract(OcrResult ocr, {required DateTime takenAt});
}

/// Progress events while the chat engine works on a question.
sealed class ChatProgress {
  const ChatProgress();
}

/// The agent called a tool. [entry] is what "How this was found" will show.
final class ChatToolUsed extends ChatProgress {
  const ChatToolUsed(this.entry);

  final ToolTraceEntry entry;
}

/// The final assistant message, already saved.
final class ChatAnswered extends ChatProgress {
  const ChatAnswered(this.message);

  final ChatMessage message;
}

/// The turn could not complete. The user message is still saved.
final class ChatFailed extends ChatProgress {
  const ChatFailed(this.message, {this.retryable = true});

  final String message;
  final bool retryable;
}

/// How Ask will answer right now, shown in the chat header.
@immutable
class ChatAvailability {
  const ChatAvailability.model({
    required this.providerName,
    required this.modelId,
  }) : searchOnly = false;

  const ChatAvailability.searchOnly()
    : searchOnly = true,
      providerName = null,
      modelId = null;

  final bool searchOnly;
  final String? providerName;
  final String? modelId;
}

/// Conversational access to memories. See docs/architecture.md, section 9.
abstract interface class ChatEngine {
  Future<Conversation> startConversation({String? title});

  /// Saves the user message, answers it, and emits progress. The stream ends
  /// after [ChatAnswered] or [ChatFailed].
  ///
  /// [focusMemoryId] scopes the first search to one memory, for "Ask about
  /// this" on the detail screen.
  Stream<ChatProgress> ask(
    String conversationId,
    String text, {
    String? focusMemoryId,
  });

  Future<ChatAvailability> availability();
}
