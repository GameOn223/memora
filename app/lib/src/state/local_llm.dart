import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

import '../widgets/memory_labels.dart';
import '../widgets/problem_dialog.dart';
import 'services.dart';
import 'settings.dart';

/// The on-device models section: what the catalog offers, what is installed,
/// and whatever the last import had to say.
@immutable
class LocalLlmView {
  const LocalLlmView({
    required this.models,
    this.importing,
    this.progress,
    this.problem,
    this.problemLink,
    this.hasToken = false,
  });

  final List<LocalLlmStatus> models;

  /// Model id being fetched right now, whether downloaded or imported.
  final String? importing;

  /// Progress from 0 to 1, when the transfer reported any.
  final double? progress;

  /// What went wrong last time, in words a person can act on.
  final String? problem;

  /// The page that settles [problem], when there is one to open.
  final ProblemLink? problemLink;

  /// Whether an access token is saved. Without one there is nothing to
  /// download with, so the row asks for one first.
  final bool hasToken;

  bool get busy => importing != null;

  LocalLlmStatus? get installed {
    for (final model in models) {
      if (model.isInstalled) return model;
    }
    return null;
  }
}

/// Fires while a generative model is being read into memory, and again with
/// null once it is loaded or has failed.
final llmLoadingProvider = StreamProvider<LlmLoading?>(
  (ref) => ref.watch(appServicesProvider).localLlm.loading,
);

final localLlmProvider =
    AsyncNotifierProvider<LocalLlmController, LocalLlmView>(
      LocalLlmController.new,
    );

class LocalLlmController extends AsyncNotifier<LocalLlmView> {
  /// Secret store key holding the Hugging Face read token. It sits with the
  /// provider API keys, under the same Keystore key, and never goes in the
  /// database or an export.
  static const tokenKey = 'huggingface.token';

  @override
  Future<LocalLlmView> build() async {
    final services = ref.watch(appServicesProvider);
    final models = await services.localLlm.list();
    final token = await services.secrets.read(tokenKey);
    // A download keeps going with Memora in the background, so settings
    // opened later picks it back up instead of offering to start it again.
    final running = await services.localLlm.activeDownload();
    if (running != null) {
      unawaited(_follow(services.localLlm.watchDownload(running), running));
    }
    return LocalLlmView(
      models: models,
      importing: running,
      hasToken: token != null && token.isNotEmpty,
    );
  }

  /// Stops the running download.
  Future<void> cancelDownload() async {
    await ref.read(appServicesProvider).localLlm.cancelDownload();
    await _reload();
  }

  /// Saves the access token, or clears it when [token] is empty.
  Future<void> saveToken(String token) async {
    final trimmed = token.trim();
    final secrets = ref.read(appServicesProvider).secrets;
    if (trimmed.isEmpty) {
      await secrets.delete(tokenKey);
    } else {
      await secrets.write(tokenKey, trimmed);
    }
    await _reload();
  }

  /// Downloads the model from its repository using the saved token.
  Future<void> download(String modelId) async {
    final view = state.value;
    if (view == null || view.busy) return;
    final services = ref.read(appServicesProvider);
    final token = await services.secrets.read(tokenKey);
    if (token == null || token.isEmpty) {
      await _reload(
        problem:
            'Paste a Hugging Face read token first. The weights are behind '
            'a licence, so there is no link that works without one.',
      );
      return;
    }
    // Nothing transferred yet, so no fraction to show.
    _show(view.models, importing: modelId, hasToken: true);
    await _follow(services.localLlm.download(modelId, token: token), modelId);
  }

  /// Turns a download's events into the view, until it ends.
  ///
  /// Shared by starting one and by picking up one already running, which
  /// look the same from here on.
  Future<void> _follow(Stream<ModelImportEvent> events, String modelId) async {
    final models = state.value?.models ?? const <LocalLlmStatus>[];
    String? problem;
    ProblemLink? link;
    try {
      await for (final event in events) {
        switch (event) {
          case ModelImportCopying(:final fraction):
            _show(
              models,
              importing: modelId,
              progress: fraction,
              hasToken: true,
            );
          case ModelImportDone():
            problem = null;
          case ModelImportCancelled():
            break;
          case ModelImportRefused(:final reason, :final fileName):
            problem = refusalMessage(
              reason,
              modelId: modelId,
              fileName: fileName,
            );
            link = refusalLink(reason, modelId: modelId);
        }
      }
    } on Object {
      problem = 'That download could not be finished. Try again.';
    }
    await _reload(problem: problem, problemLink: link);
  }

  /// Opens the picker, copies the file in and refreshes the list.
  Future<void> import(String modelId) async {
    final view = state.value;
    if (view == null || view.busy) return;
    final services = ref.read(appServicesProvider);
    // No fraction yet: the picker is still open, and until the copy says
    // something a bar with no end is the honest one.
    _show(view.models, importing: modelId);

    String? problem;
    ProblemLink? link;
    try {
      await for (final event in services.localLlm.import(modelId)) {
        switch (event) {
          case ModelImportCopying(:final fraction):
            _show(view.models, importing: modelId, progress: fraction);
          case ModelImportDone():
            problem = null;
          case ModelImportCancelled():
            break;
          case ModelImportRefused(:final reason, :final fileName):
            problem = refusalMessage(
              reason,
              modelId: modelId,
              fileName: fileName,
            );
            link = refusalLink(reason, modelId: modelId);
        }
      }
    } on Object {
      problem = 'That file could not be imported. Try again.';
    }
    await _reload(problem: problem, problemLink: link);
  }

  Future<void> remove(String modelId) async {
    final view = state.value;
    if (view == null || view.busy) return;
    await ref.read(appServicesProvider).localLlm.remove(modelId);
    await _reload();
  }

  /// Says what to do about a file that cannot be used.
  static String refusalMessage(
    ModelImportRefusal reason, {
    required String modelId,
    String? fileName,
  }) {
    final spec = localLlmSpec(modelId);
    final kind = spec?.fileExtensions.first ?? '.task';
    final named = fileName == null ? null : '"$fileName"';
    return switch (reason) {
      ModelImportRefusal.wrongFileType =>
        '${named ?? 'That file'} is not a $kind model. Download the $kind '
            'file from the ${spec?.sourceName ?? 'model'} page and import '
            'that one.',
      ModelImportRefusal.notEnoughStorage =>
        'There is not enough free space for '
            '${byteSize(spec?.approximateBytes ?? 0)}. Free some up and try '
            'again.',
      ModelImportRefusal.unreadable =>
        'Memora could not read ${named ?? 'that file'}. Copy it to this '
            'phone first, then import it.',
      ModelImportRefusal.tokenRejected =>
        'Hugging Face would not take that token. Check you pasted a read '
            'token, all of it, then try again.',
      ModelImportRefusal.licenceNotAccepted => switch (spec?.gate) {
        ModelGate.manual =>
          'The token works, but ${spec?.displayName ?? 'this model'} is '
              'granted by hand. Request access on its page, then download '
              'once that comes through.',
        _ =>
          'The token works, but this account has not accepted the '
              '${spec?.licence ?? 'licence'}. Accept it on the model page, '
              'then try again.',
      },
      ModelImportRefusal.downloadFailed =>
        'The download stopped before it was finished. Nothing was kept, so '
            'trying again starts clean.',
    };
  }

  /// The page that settles a refusal, when opening one would help.
  ///
  /// A rejected token is settled on the token page, a licence on the
  /// model page. Running out of space or a broken transfer have no page
  /// worth sending anyone to.
  static ProblemLink? refusalLink(
    ModelImportRefusal reason, {
    required String modelId,
  }) {
    final spec = localLlmSpec(modelId);
    return switch (reason) {
      ModelImportRefusal.tokenRejected => const ProblemLink(
        label: 'Get a token',
        url: tokensUrl,
      ),
      ModelImportRefusal.licenceNotAccepted ||
      ModelImportRefusal.wrongFileType when spec != null => ProblemLink(
        label: spec.gate == ModelGate.manual
            ? 'Request access'
            : 'Open the model page',
        url: spec.sourceUrl,
      ),
      _ => null,
    };
  }

  /// Where Hugging Face read tokens are made.
  static const tokensUrl = 'https://huggingface.co/settings/tokens';

  void _show(
    List<LocalLlmStatus> models, {
    String? importing,
    double? progress,
    String? problem,
    ProblemLink? problemLink,
    bool? hasToken,
  }) {
    state = AsyncData(
      LocalLlmView(
        models: models,
        importing: importing,
        progress: progress,
        problem: problem,
        problemLink: problemLink,
        hasToken: hasToken ?? state.value?.hasToken ?? false,
      ),
    );
  }

  Future<void> _reload({String? problem, ProblemLink? problemLink}) async {
    final services = ref.read(appServicesProvider);
    final models = await services.localLlm.list();
    final token = await services.secrets.read(tokenKey);
    _show(
      models,
      problem: problem,
      problemLink: problemLink,
      hasToken: token != null && token.isNotEmpty,
    );
    // Installing or deleting a model changes what chat and vision can do.
    ref.invalidate(capabilityStatusesProvider);
    ref.invalidate(chatAvailabilityProvider);
  }
}
