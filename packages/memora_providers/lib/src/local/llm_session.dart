import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'llm_prompt.dart';
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
    await _load(capability);
    final stream = _runtime.generate(
      prompt,
      images: images,
      maxTokens: maxOutputTokens,
    );
    final reply = await _collect(
      stream,
      maxChars: maxOutputTokens * charsPerToken,
    );
    return _trim(reply);
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
    await _runtime.load(
      model.relativePath,
      vision: spec.vision,
      maxTokens: spec.maxTokens,
    );
  }

  /// Collects generated pieces, stopping at the end of the model's turn or
  /// at [maxChars], and cancelling the stream either way.
  Future<String> _collect(
    Stream<String> chunks, {
    required int maxChars,
  }) async {
    final out = StringBuffer();
    try {
      // Returning from here cancels the subscription, which tells the
      // runtime to stop generating.
      await for (final chunk in chunks) {
        out.write(chunk);
        final text = out.toString();
        final end = text.indexOf(LocalLlmPrompt.endTurn);
        if (end != -1) return text.substring(0, end);
        if (text.length >= maxChars) return text;
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(_failure(error), stack);
    }
    return out.toString();
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

  static String _trim(String reply) {
    var text = reply;
    for (final marker in [
      LocalLlmPrompt.endTurn,
      LocalLlmPrompt.startModel,
      LocalLlmPrompt.startUser,
      '<start_of_turn>',
    ]) {
      text = text.replaceAll(marker, '');
    }
    return text.trim();
  }
}
