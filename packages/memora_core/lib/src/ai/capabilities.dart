import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../model/understanding.dart';
import '../ports/embedding_model.dart';

/// An image to understand.
@immutable
class VisionRequest {
  const VisionRequest({
    required this.imageBytes,
    required this.mimeType,
    required this.takenAt,
    this.absoluteImagePath,
    this.localeTag = 'en-IN',
    this.defaultCurrency = 'INR',
  });

  final Uint8List imageBytes;
  final String mimeType;

  /// Path of the original on disk. On-device adapters that read files, such
  /// as OCR, use this instead of the bytes.
  final String? absoluteImagePath;

  /// Currency assumed when the image only shows a symbol such as Rs.
  final String defaultCurrency;

  /// Helps the model resolve relative dates such as "due tomorrow".
  final DateTime takenAt;

  /// BCP 47 tag used for default currency and date order hints.
  final String localeTag;
}

/// A narrow check of one stored fact against the original image.
@immutable
class VerificationRequest {
  const VerificationRequest({
    required this.imageBytes,
    required this.mimeType,
    required this.attributeType,
    required this.expectedValue,
    this.absoluteImagePath,
  });

  final Uint8List imageBytes;
  final String mimeType;
  final String? absoluteImagePath;

  /// For example `amount`.
  final String attributeType;

  /// For example `₹2,103`.
  final String expectedValue;
}

@immutable
class VerificationResult {
  const VerificationResult({required this.confirmed, this.observedValue});

  final bool confirmed;

  /// What the model read in the image, when it differs or is unsure.
  final String? observedValue;
}

abstract interface class VisionService {
  Future<MemoryUnderstanding> analyze(VisionRequest request);

  Future<VerificationResult> verify(VerificationRequest request);
}

/// A tool the chat model may call. [parameters] is a JSON schema object.
@immutable
class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

/// A tool call requested by the chat model.
@immutable
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

/// One entry in a chat transcript sent to a model.
sealed class ChatEntry {
  const ChatEntry();
}

final class UserEntry extends ChatEntry {
  const UserEntry(this.text);

  final String text;
}

final class AssistantEntry extends ChatEntry {
  const AssistantEntry({this.text = '', this.toolCalls = const []});

  final String text;
  final List<ToolCall> toolCalls;
}

final class ToolResultEntry extends ChatEntry {
  const ToolResultEntry({
    required this.callId,
    required this.toolName,
    required this.content,
    this.isError = false,
  });

  final String callId;
  final String toolName;

  /// JSON text returned to the model.
  final String content;
  final bool isError;
}

@immutable
class ChatRequest {
  const ChatRequest({
    required this.system,
    required this.entries,
    this.tools = const [],
    this.maxOutputTokens = 1024,
    this.temperature = 0.2,
  });

  final String system;
  final List<ChatEntry> entries;
  final List<ToolDefinition> tools;
  final int maxOutputTokens;
  final double temperature;
}

enum ChatStopReason { endTurn, toolUse, maxTokens, other }

@immutable
class ChatTurn {
  const ChatTurn({
    required this.text,
    required this.toolCalls,
    required this.stopReason,
  });

  final String text;
  final List<ToolCall> toolCalls;
  final ChatStopReason stopReason;
}

abstract interface class ChatService {
  Future<ChatTurn> complete(ChatRequest request);
}

/// Some embedding models encode queries and documents differently.
enum EmbeddingPurpose { document, query }

abstract interface class EmbeddingService {
  EmbeddingModelInfo get model;

  /// Returns one L2-normalized vector per text, in order.
  Future<List<Float32List>> embed(
    List<String> texts, {
    EmbeddingPurpose purpose = EmbeddingPurpose.document,
  });
}

@immutable
class RerankCandidate {
  const RerankCandidate({
    required this.id,
    required this.text,
    this.priorScore = 0,
    this.entities = const [],
    this.category,
    this.takenAt,
  });

  final String id;
  final String text;

  /// Score from first-stage retrieval, available to local rerankers.
  final double priorScore;

  /// Entity values for this memory. A remote reranker sees only [text]; the
  /// on-device one uses these for exact name matches.
  final List<String> entities;

  /// The memory's category, for matching a category word in the question.
  final String? category;

  /// When the image was taken, used as a small recency tie-break.
  final DateTime? takenAt;
}

@immutable
class RerankScore {
  const RerankScore(this.id, this.score);

  final String id;
  final double score;
}

abstract interface class RerankService {
  /// Returns scores for every candidate, best first.
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  );
}
