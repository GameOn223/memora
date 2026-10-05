import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/memora_providers.dart';

import '../widgets/memory_labels.dart';
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
  });

  final List<LocalLlmStatus> models;

  /// Model id being imported right now.
  final String? importing;

  /// Copy progress from 0 to 1, when the picker reported any.
  final double? progress;

  /// What went wrong with the last import, in words a person can act on.
  final String? problem;

  bool get busy => importing != null;

  LocalLlmStatus? get installed {
    for (final model in models) {
      if (model.isInstalled) return model;
    }
    return null;
  }
}

final localLlmProvider =
    AsyncNotifierProvider<LocalLlmController, LocalLlmView>(
      LocalLlmController.new,
    );

class LocalLlmController extends AsyncNotifier<LocalLlmView> {
  @override
  Future<LocalLlmView> build() async {
    final models = await ref.watch(appServicesProvider).localLlm.list();
    return LocalLlmView(models: models);
  }

  /// Opens the picker, copies the file in and refreshes the list.
  Future<void> import(String modelId) async {
    final view = state.value;
    if (view == null || view.busy) return;
    final services = ref.read(appServicesProvider);
    _show(view.models, importing: modelId, progress: 0);

    String? problem;
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
        }
      }
    } on Object {
      problem = 'That file could not be imported. Try again.';
    }
    await _reload(problem: problem);
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
    };
  }

  void _show(
    List<LocalLlmStatus> models, {
    String? importing,
    double? progress,
    String? problem,
  }) {
    state = AsyncData(
      LocalLlmView(
        models: models,
        importing: importing,
        progress: progress,
        problem: problem,
      ),
    );
  }

  Future<void> _reload({String? problem}) async {
    final models = await ref.read(appServicesProvider).localLlm.list();
    _show(models, problem: problem);
    // Installing or deleting a model changes what chat and vision can do.
    ref.invalidate(capabilityStatusesProvider);
    ref.invalidate(chatAvailabilityProvider);
  }
}
