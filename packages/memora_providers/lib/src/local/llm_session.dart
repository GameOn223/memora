import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'llm_reply_filter.dart';
import 'model_catalog.dart';

/// Loads the model the user imported and turns one prompt into one reply.
///
/// Generation arrives a piece at a time. This collects the pieces and stops
/// reading as soon as the reply is complete: Gemma writes `<end_of_turn>`
/// when it is done, and a small model sometimes carries on past it with
/// another invented turn. Cancelling there saves the rest of the tokens, and
/// with them the battery they would cost.
class LocalLlmSession {
  LocalLlmSession({
    required this._runtime,
    required this._files,
    required this.spec,
  });

  static const providerId = 'local';

  /// Roughly how many characters a token is worth, for the runaway guard.
  static const charsPerToken = 6;

  final LocalLlmRuntime _runtime;
  final LocalLlmFiles _files;
  final LocalLlmSpec spec;

  /// Runs [prompt] and returns the reply with the turn markers removed.
  ///
  /// [capability] names the capability in the error when the model file is
  /// not on the phone.
  Future<String> run(
    String prompt, {
    required Capability capability,
    List<Uint8List> images = const [],
    int maxOutputTokens = 1024,
  }) async {
    final out = StringBuffer();
    await for (final piece in runStreaming(
      prompt,
      capability: capability,
      images: images,
      maxOutputTokens: maxOutputTokens,
    )) {
      out.write(piece);
    }
    return out.toString();
  }

  /// Runs [prompt] and hands over the reply as it is produced.
  ///
  /// Each piece is new text with the turn markers already gone, so a caller
  /// can show it the moment it arrives. The pieces joined together are
  /// exactly what [run] returns.
  Stream<String> runStreaming(
    String prompt, {
    required Capability capability,
    List<Uint8List> images = const [],
    int maxOutputTokens = 1024,
  }) async* {
    await _load(capability);
    final stream = _runtime.generate(
      prompt,
      images: images,
      maxTokens: maxOutputTokens,
    );
    yield* _trimmed(stream, maxChars: maxOutputTokens * charsPerToken);
  }

  /// Loads the file for [spec] unless the runtime already holds it.
  Future<void> _load(Capability capability) async {
    InstalledLlmModel? model;
    for (final candidate in await _files.installed()) {
      if (candidate.modelId == spec.id) {
        model = candidate;
        break;
      }
    }
    if (model == null) {
      throw CapabilityUnavailableException(
        capability,
        UnavailableReason.modelNotDownloaded,
        providerName: 'On this device',
        modelId: spec.id,
      );
    }
    final loaded = await _runtime.loadedModelPath();
    if (loaded == model.relativePath && await _runtime.isLoaded()) return;
    await _loadWithFallback(model.relativePath);
  }

  /// Loads the file, trying smaller context sizes if the runtime refuses.
  ///
  /// A `.task` bundle carries a KV cache of a fixed size and MediaPipe will
  /// not load one asked for more tokens than it was built with. The size is
  /// not in the file name reliably and nothing reports it before loading, so
  /// the way to find out is to ask for less. A model that works at 1280
  /// tokens is worth far more than a clear explanation of why it will not
  /// load at 4096.
  ///
  /// Anything that is not about the size is rethrown on the first attempt.
  Future<void> _loadWithFallback(String relativePath) async {
    final sizes = spec.tokenFallbacks;
    for (var i = 0; i < sizes.length; i++) {
      try {
        await _runtime.load(
          relativePath,
          vision: spec.vision,
          maxTokens: sizes[i],
        );
        return;
      } on AiConfigurationException catch (error) {
        final last = i == sizes.length - 1;
        if (last || !_mightBeTheContextSize(error)) rethrow;
      }
    }
  }

  /// Whether a refusal could be about the context size rather than the file
  /// or the phone. Running out of memory is about the phone, and a model
  /// that is simply too large will not load at any context size.
  static bool _mightBeTheContextSize(AiConfigurationException error) {
    final message = error.message.toLowerCase();
    return !message.contains('out of memory') &&
        !message.contains('another runtime') &&
        !message.contains('processor');
  }

  /// Hands over generated text with the markers gone, stopping at the end
  /// of the model's turn or at [maxChars] and cancelling the stream either
  /// way.
  Stream<String> _trimmed(
    Stream<String> chunks, {
    required int maxChars,
  }) async* {
    final filter = LocalReplyFilter(maxChars: maxChars);
    try {
      // Returning from here cancels the subscription, which tells the
      // runtime to stop generating.
      await for (final chunk in chunks) {
        final text = filter.add(chunk);
        if (text.isNotEmpty) yield text;
        if (filter.done) return;
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(_failure(error), stack);
    }
    final rest = filter.finish();
    if (rest.isNotEmpty) yield rest;
  }

  /// Anything the native runtime throws is worth another attempt: it ran out
  /// of memory, the model was unloaded under it, or the engine died. Nothing
  /// about the prompt changes by retrying, but nothing about it is wrong
  /// either, so this never fails a memory for good.
  Object _failure(Object error) =>
      error is AiException || error is CapabilityUnavailableException
      ? error
      : AiTransientException(
          'The on-device model stopped: $error',
          providerId: providerId,
        );
}
