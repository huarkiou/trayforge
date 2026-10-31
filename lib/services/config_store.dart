import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';

/// Configuration persistence layer.
///
/// Reads and writes [AppConfig] to `config.json` under [dataDir],
/// with automatic backup and validation.
///
/// ConfigStore is a pure persistence module — it does not broadcast
/// changes. Callers (typically [ProcessManager]) are responsible for
/// notifying downstream consumers after a config write.
class ConfigStore {
  final String dataDir;
  final int maxBackupBytes;

  ConfigStore({String? dataDir, this.maxBackupBytes = 10 * 1024 * 1024})
    : dataDir = dataDir ?? Logger.getDataDir();

  String get _configPath => p.join(dataDir, 'config.json');
  String get _backupsDir => p.join(dataDir, 'backups');

  /// Loads the configuration from disk.
  ///
  /// Returns an [AppConfig] parsed from `config.json`.
  /// Returns `null` if the file does not exist.
  /// On JSON parse or type error, backs up the corrupted file to
  /// `backups/config.<timestamp>.corrupted.json` and returns `null`.
  AppConfig? load() {
    final file = File(_configPath);
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync(encoding: utf8);
      final json = jsonDecode(content) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } on FormatException {
      _backupCorrupted(file);
      return null;
    } on TypeError {
      _backupCorrupted(file);
      return null;
    }
  }

  /// Saves [config] to `config.json`.
  ///
  /// Creates the data directory if needed. Backs up the existing config
  /// file to `backups/config.<timestamp>.json` before overwriting, then
  /// prunes old backup files if the backup directory exceeds [maxBackupBytes].
  void save(AppConfig config) {
    _backupExisting();

    final dir = Directory(dataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final json = config.toJson();
    final encoded = const JsonEncoder.withIndent('  ').convert(json);
    File(_configPath).writeAsStringSync(encoded, encoding: utf8, flush: true);

    _prune();
  }

  /// Validates a single [UnitConfig], applying the rules of its kind.
  ///
  /// Throws [ArgumentError] if:
  /// - the unit name is empty or whitespace-only
  /// - the unit name contains `/` or `\`
  /// - a [ProcessConfig.webuiPattern] is non-null and not a valid regex
  /// - a [ServiceConfig] has no services
  void validate(UnitConfig unit) {
    _validateName(unit.name, what: _kindLabel(unit));

    switch (unit) {
      case ProcessConfig(:final webuiPattern):
        if (webuiPattern == null) return;
        try {
          RegExp(webuiPattern);
        } on FormatException catch (e) {
          throw ArgumentError('Invalid webui_pattern regex: ${e.message}');
        }
      case ServiceConfig(:final services):
        if (services.isEmpty) {
          throw ArgumentError(
            'Service group "${unit.name}" needs at least one service',
          );
        }
    }
  }

  /// The name rules shared by every managed kind.
  void _validateName(String name, {required String what}) {
    if (name.trim().isEmpty) {
      throw ArgumentError('$what name must not be empty');
    }

    if (name.contains('/') || name.contains('\\')) {
      throw ArgumentError('$what name "$name" must not contain / or \\');
    }
  }

  /// The human label for a unit's kind, used in validation messages.
  static String _kindLabel(UnitConfig unit) => switch (unit) {
    ProcessConfig() => 'Process',
    ServiceConfig() => 'Service group',
  };

  // ---- Private helpers ----

  void _backupCorrupted(File file) {
    _ensureBackupsDir();
    final dest = p.join(_backupsDir, 'config.${_timestamp()}.corrupted.json');
    file.copySync(dest);
  }

  void _backupExisting() {
    final file = File(_configPath);
    if (!file.existsSync()) return;

    _ensureBackupsDir();
    final dest = p.join(_backupsDir, 'config.${_timestamp()}.json');
    file.copySync(dest);
  }

  void _ensureBackupsDir() {
    final dir = Directory(_backupsDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  void _prune() {
    final dir = Directory(_backupsDir);
    if (!dir.existsSync()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('config.'))
        .toList();

    // Sort by name (timestamp embedded in name), oldest first.
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    var totalSize = files.fold<int>(0, (sum, f) => sum + f.lengthSync());

    for (final file in files) {
      if (totalSize <= maxBackupBytes) break;
      final size = file.lengthSync();
      file.deleteSync();
      totalSize -= size;
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}'
        '.${_pad(now.millisecond)}.${_pad6(now.microsecond)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _pad6(int n) => n.toString().padLeft(6, '0');
}
