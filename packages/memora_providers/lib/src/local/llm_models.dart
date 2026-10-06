import 'package:memora_core/memora_core.dart';

import 'model_catalog.dart';

/// Whether this phone can hold a model while it runs.
enum LocalLlmFit {
  /// Enough free RAM right now.
  fits,

  /// The phone has the memory but not much of it free. Loading may fail
  /// until something else closes.
  tight,

  /// The phone does not have the memory at all. Say so before a download of
  /// several gigabytes, not after.
  tooSmall,

  /// No runtime to ask.
  unknown,
}

/// One catalog entry, what the phone can do with it, and whether its file is
/// already here.
class LocalLlmStatus {
  const LocalLlmStatus({
    required this.spec,
    required this.fit,
    this.installed,
    this.device,
  });

  final LocalLlmSpec spec;
  final LocalLlmFit fit;

  /// The file in app storage, when it was imported.
  final InstalledLlmModel? installed;

  /// What the runtime reported, for the UI to show plainly.
  final DeviceMemory? device;

  bool get isInstalled => installed != null;

  /// Whether importing is worth offering. A phone that cannot run the model
  /// is not asked to fetch three gigabytes first.
  bool get canImport => !isInstalled && fit != LocalLlmFit.tooSmall;
}

/// The on-device generative models settings offers, with install state and
/// an honest answer about this phone.
///
/// The ports are optional because the native runtime belongs to the platform
/// layer. Without one, [supported] is false and settings leaves the section
/// out rather than offering a model that has nothing to run in.
class LocalLlmModels {
  const LocalLlmModels({
    this._runtime,
    this._files,
    this.catalog = localLlmCatalog,
  });

  final LocalLlmRuntime? _runtime;
  final LocalLlmFiles? _files;
  final List<LocalLlmSpec> catalog;

  bool get supported => _runtime != null && _files != null;

  /// Every catalog entry, smallest first.
  Future<List<LocalLlmStatus>> list() async {
    final runtime = _runtime;
    final files = _files;
    if (runtime == null || files == null) {
      return [
        for (final spec in catalog)
          LocalLlmStatus(spec: spec, fit: LocalLlmFit.unknown),
      ];
    }
    final installed = await files.installed();
    final device = await runtime.memory();
    return [
      for (final spec in catalog)
        LocalLlmStatus(
          spec: spec,
          fit: fitFor(spec, device),
          device: device,
          installed: _installedFor(spec.id, installed),
        ),
    ];
  }

  /// Opens the picker and brings a file in. Emits copy progress, then one
  /// closing event.
  Stream<ModelImportEvent> import(String modelId) {
    final files = _files;
    final spec = localLlmSpec(modelId);
    if (files == null || spec == null) {
      return Stream.value(
        const ModelImportRefused(ModelImportRefusal.unreadable),
      );
    }
    return files.import(modelId, extensions: spec.fileExtensions);
  }

  /// Fetches the weights straight from the model's repository with [token].
  Stream<ModelImportEvent> download(String modelId, {required String token}) {
    final files = _files;
    if (files == null || localLlmSpec(modelId) == null) {
      return Stream.value(
        const ModelImportRefused(ModelImportRefusal.unreadable),
      );
    }
    return files.download(modelId, token: token);
  }

  /// Deletes the file and unloads the model if it was the one running.
  Future<void> remove(String modelId) async {
    final files = _files;
    if (files == null) return;
    await files.remove(modelId);
    await _runtime?.unload();
  }

  static LocalLlmFit fitFor(LocalLlmSpec spec, DeviceMemory device) {
    if (device.lowRamDevice || device.totalBytes < spec.requiredMemoryBytes) {
      return LocalLlmFit.tooSmall;
    }
    return device.availableBytes < spec.requiredMemoryBytes
        ? LocalLlmFit.tight
        : LocalLlmFit.fits;
  }

  static InstalledLlmModel? _installedFor(
    String modelId,
    List<InstalledLlmModel> installed,
  ) {
    for (final model in installed) {
      if (model.modelId == modelId) return model;
    }
    return null;
  }
}
