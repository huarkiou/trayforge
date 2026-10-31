import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';

/// A fake [ConfigStore] that keeps an in-memory config and records saves.
///
/// Unlike stubbing-only fakes, every [save] is captured so tests can
/// assert what would have been written to `config.json` — e.g. a
/// reordered unit list or carried-over globals like
/// `dashboard_layout`.
class RecordingConfigStore extends Fake implements ConfigStore {
  /// The current config; [load] returns this. Updated on every [save].
  AppConfig? config;

  /// Every config passed to [save], in call order.
  final List<AppConfig> saved = [];

  /// Applies the real validation rules; [Fake] would otherwise throw on
  /// [validate], which the settings view model calls before every add/edit.
  final ConfigStore _validator = ConfigStore(dataDir: 'unused');

  RecordingConfigStore([this.config]);

  @override
  AppConfig? load() => config;

  @override
  void save(AppConfig value) {
    saved.add(value);
    config = value;
  }

  @override
  void validate(UnitConfig unit) => _validator.validate(unit);

  /// The most recently saved config, or `null` if [save] was never called.
  AppConfig? get lastSaved => saved.isEmpty ? null : saved.last;
}
