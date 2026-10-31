/// Core data types for the trayforge application.
library;

/// The lifecycle state of a managed process.
enum ProcState { stopped, starting, running, stopping, crashed, cooldown }

/// Extension on [ProcState] providing derived semantics.
extension ProcStateX on ProcState {
  /// Whether the process is actively running or starting.
  bool get isActive => this == ProcState.running || this == ProcState.starting;

  /// Whether the process is in a terminal (non-transitioning) state.
  bool get isTerminal =>
      this != ProcState.starting && this != ProcState.stopping;

  /// Short display label for the state.
  String get label {
    switch (this) {
      case ProcState.stopped:
        return 'Stopped';
      case ProcState.starting:
        return 'Starting';
      case ProcState.running:
        return 'Running';
      case ProcState.stopping:
        return 'Stopping';
      case ProcState.crashed:
        return 'Crashed';
      case ProcState.cooldown:
        return 'Cooldown';
    }
  }
}

/// The layout mode of the Dashboard process list.
enum DashboardLayout { list, grid }

/// The two kinds of unit, and the strings each kind is known by.
///
/// One vocabulary, three uses: the `kind` discriminator in `config.json`, the
/// human label in validation messages, and the prefix of the stable ids the
/// dashboard and tray key their cards and menu items by.
enum UnitKind {
  process('process', 'Process', 'proc:'),
  service('service', 'Service group', 'svc:');

  const UnitKind(this.jsonValue, this.label, this.keyPrefix);

  /// The `kind` value in `config.json`.
  final String jsonValue;

  /// Human label, used in validation messages.
  final String label;

  /// Prefix of the stable ids the dashboard and tray use (`proc:<name>`).
  final String keyPrefix;

  /// Parses a JSON `kind`, or `null` when it is not one of the two.
  static UnitKind? tryParse(String value) {
    for (final kind in UnitKind.values) {
      if (kind.jsonValue == value) return kind;
    }
    return null;
  }
}

/// One dashboard unit: whatever TrayForge shows as a single card and manages
/// as one thing.
///
/// Exactly two kinds exist — a [ProcessConfig] and a [ServiceConfig] — and the
/// configuration keeps them in one ordered [AppConfig.units] list, so the
/// dashboard can interleave them in any order the user arranged.
sealed class UnitConfig {
  const UnitConfig();

  /// Which kind of unit this is.
  UnitKind get kind;

  /// Display name.
  ///
  /// Names are unique within their kind. Cards and menu items are keyed by
  /// kind + name ([UnitKind.keyPrefix] followed by the name), so a process and
  /// a service group may share a label without colliding.
  String get name;

  /// The kind-specific fields, without the `kind` discriminator.
  ///
  /// [AppConfig] adds `kind` when writing the units array; a unit serialized on
  /// its own has no kind to declare.
  Map<String, dynamic> toJson();

  /// A copy of this unit carrying [newName].
  ///
  /// Copies and renames go through this instead of a per-kind `copyWith` so
  /// callers that only know they have a unit can still build one.
  UnitConfig renamed(String newName);
}

/// Configuration for a single managed process.
class ProcessConfig extends UnitConfig {
  @override
  final String name;
  final String? cwd;
  final String cmd;
  final String? encoding;
  final bool singleton;
  final bool autostart;
  final String? webuiPattern;
  final List<String> deleteBeforeStart;
  final int? maxRestarts;
  final Map<String, String>? env;
  final bool cleanupCwd;

  /// Launch this process elevated (Windows: UAC consent prompt).
  ///
  /// The elevated child is created through the UAC broker, so it gets its own
  /// console instead of the parent's stdout/stderr pipes: its output is **not**
  /// captured by trayforge, and its environment is not the one built here.
  /// Exit code and termination still work — the broker's process handle is
  /// kept for that. Pair with [logFile] to see output at all.
  final bool elevated;

  /// Log file to tail into the output pane, or `null` for none.
  ///
  /// Relative paths are resolved against [cwd]. Only lines appended after the
  /// launch are shown, so a long-running process does not replay its backlog.
  /// This is the only way to see output from an [elevated] process.
  final String? logFile;

  const ProcessConfig({
    required this.name,
    this.cwd,
    required this.cmd,
    this.encoding,
    this.singleton = false,
    this.autostart = false,
    this.webuiPattern,
    this.deleteBeforeStart = const [],
    this.maxRestarts,
    this.env,
    this.cleanupCwd = false,
    this.elevated = false,
    this.logFile,
  });

  @override
  UnitKind get kind => UnitKind.process;

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    if (cwd != null) 'cwd': cwd,
    'cmd': cmd,
    if (encoding != null) 'encoding': encoding,
    'singleton': singleton,
    'autostart': autostart,
    if (webuiPattern != null) 'webui_pattern': webuiPattern,
    'delete_before_start': deleteBeforeStart,
    if (maxRestarts != null) 'max_restarts': maxRestarts,
    if (env != null) 'env': env,
    'cleanup_cwd': cleanupCwd,
    if (elevated) 'elevated': true,
    if (logFile != null) 'log_file': logFile,
  };

  factory ProcessConfig.fromJson(Map<String, dynamic> json) {
    return ProcessConfig(
      name: json['name'] as String,
      cwd: json['cwd'] as String?,
      cmd: json['cmd'] as String,
      encoding: json['encoding'] as String?,
      singleton: json['singleton'] as bool? ?? false,
      autostart: json['autostart'] as bool? ?? false,
      webuiPattern: json['webui_pattern'] as String?,
      deleteBeforeStart: _parseStringList(json['delete_before_start']),
      maxRestarts: json['max_restarts'] as int?,
      env: (json['env'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      cleanupCwd: json['cleanup_cwd'] as bool? ?? false,
      elevated: json['elevated'] as bool? ?? false,
      logFile: json['log_file'] as String?,
    );
  }

  /// Parses a JSON value that should be a list of strings.
  ///
  /// Accepts a [List] (Python trayforge format). Returns `[]` for
  /// any other type (e.g. old Flutter `bool` format) or when missing.
  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  ProcessConfig copyWith({
    String? name,
    String? cwd,
    String? cmd,
    String? encoding,
    bool? singleton,
    bool? autostart,
    String? webuiPattern,
    List<String>? deleteBeforeStart,
    int? maxRestarts,
    Map<String, String>? env,
    bool? cleanupCwd,
    bool? elevated,
    String? logFile,
  }) {
    return ProcessConfig(
      name: name ?? this.name,
      cwd: cwd ?? this.cwd,
      cmd: cmd ?? this.cmd,
      encoding: encoding ?? this.encoding,
      singleton: singleton ?? this.singleton,
      autostart: autostart ?? this.autostart,
      webuiPattern: webuiPattern ?? this.webuiPattern,
      deleteBeforeStart: deleteBeforeStart ?? this.deleteBeforeStart,
      maxRestarts: maxRestarts ?? this.maxRestarts,
      env: env ?? this.env,
      cleanupCwd: cleanupCwd ?? this.cleanupCwd,
      elevated: elevated ?? this.elevated,
      logFile: logFile ?? this.logFile,
    );
  }

  @override
  ProcessConfig renamed(String newName) => copyWith(name: newName);
}

/// Configuration for a managed group of services (Windows SCM / systemd).
///
/// A group is the unit of management: the card shows the aggregate state and a
/// toggle drives every member to the same state (see ADR 005).
class ServiceConfig extends UnitConfig {
  @override
  final String name;

  /// Service names (Windows) or unit names (systemd), managed together.
  final List<String> services;

  /// Stop services that depend on a member before stopping the member.
  final bool stopDependents;

  const ServiceConfig({
    required this.name,
    required this.services,
    this.stopDependents = false,
  });

  @override
  UnitKind get kind => UnitKind.service;

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'services': services,
    if (stopDependents) 'stop_dependents': true,
  };

  factory ServiceConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['services'];
    return ServiceConfig(
      name: json['name'] as String,
      services: raw is List
          ? raw.map((e) => e.toString()).toList()
          : const <String>[],
      stopDependents: json['stop_dependents'] as bool? ?? false,
    );
  }

  ServiceConfig copyWith({
    String? name,
    List<String>? services,
    bool? stopDependents,
  }) {
    return ServiceConfig(
      name: name ?? this.name,
      services: services ?? this.services,
      stopDependents: stopDependents ?? this.stopDependents,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServiceConfig &&
      other.name == name &&
      other.stopDependents == stopDependents &&
      other.services.length == services.length &&
      Iterable<int>.generate(
        services.length,
      ).every((i) => other.services[i] == services[i]);

  @override
  int get hashCode =>
      Object.hash(name, stopDependents, Object.hashAll(services));

  @override
  ServiceConfig renamed(String newName) => copyWith(name: newName);
}

/// Application-level configuration.
class AppConfig {
  final int outputHistoryLimit;
  final int outputRefreshMs;

  /// How often a service group re-queries the SCM for its state.
  final int servicePollMs;

  final DashboardLayout dashboardLayout;

  /// Every managed unit in dashboard order: processes and service groups,
  /// interleaved however the user arranged them.
  ///
  /// This list *is* the order — there is no separate layout array. Reordering
  /// the dashboard moves an entry here.
  final List<UnitConfig> units;

  const AppConfig({
    this.outputHistoryLimit = 1000,
    this.outputRefreshMs = 500,
    this.servicePollMs = 5000,
    this.dashboardLayout = DashboardLayout.list,
    this.units = const [],
  });

  /// The configured processes, in dashboard order.
  List<ProcessConfig> get processes =>
      units.whereType<ProcessConfig>().toList(growable: false);

  /// The configured service groups, in dashboard order.
  List<ServiceConfig> get services =>
      units.whereType<ServiceConfig>().toList(growable: false);

  /// Default configuration with example processes: NapCat + AstrBot.
  factory AppConfig.defaultConfig() {
    return AppConfig(
      outputHistoryLimit: 1000,
      outputRefreshMs: 500,
      units: [
        const ProcessConfig(
          name: 'NapCat',
          cwd: r'C:\NapCat',
          cmd: r'napcat.exe',
          singleton: true,
          autostart: true,
          webuiPattern: r'WebUI started at (http://[\d.:]+)',
          maxRestarts: 3,
        ),
        const ProcessConfig(
          name: 'AstrBot',
          cwd: r'C:\AstrBot',
          cmd: r'astrbot.exe',
          singleton: true,
          autostart: true,
          webuiPattern: r'WebUI started at (http://[\d.:]+)',
          maxRestarts: 3,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'output_history_limit': outputHistoryLimit,
    'output_refresh_ms': outputRefreshMs,
    'service_poll_ms': servicePollMs,
    'dashboard_layout': dashboardLayout.name,
    'units': units
        .map((unit) => {'kind': unit.kind.jsonValue, ...unit.toJson()})
        .toList(),
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      outputHistoryLimit: json['output_history_limit'] as int? ?? 1000,
      outputRefreshMs: json['output_refresh_ms'] as int? ?? 500,
      servicePollMs: json['service_poll_ms'] as int? ?? 5000,
      dashboardLayout: _parseDashboardLayout(json['dashboard_layout']),
      units: _parseUnits(json),
    );
  }

  /// Parses the ordered unit list, migrating the pre-`units` schema.
  ///
  /// A config written by an older version has `processes` and `services`
  /// arrays and no `units`; it is read as "processes first, then service
  /// groups", which was the previous visual order.
  static List<UnitConfig> _parseUnits(Map<String, dynamic> json) {
    final rawUnits = json['units'];
    if (rawUnits is List) {
      return rawUnits
          .map((e) => _parseUnit(e as Map<String, dynamic>))
          .toList();
    }

    return [
      for (final raw in json['processes'] as List<dynamic>? ?? const [])
        ProcessConfig.fromJson(raw as Map<String, dynamic>),
      for (final raw in json['services'] as List<dynamic>? ?? const [])
        ServiceConfig.fromJson(raw as Map<String, dynamic>),
    ];
  }

  /// Parses one unit entry.
  ///
  /// `kind` is optional so a hand-written entry can omit it; the entry's shape
  /// then decides (`services` → service group, otherwise a process). An
  /// explicit kind wins over the shape, and an unknown kind is a config we
  /// cannot interpret, so it fails like any other parse error and
  /// [ConfigStore] backs the file up.
  static UnitConfig _parseUnit(Map<String, dynamic> json) {
    final rawKind = json['kind'];
    if (rawKind == null) {
      return json.containsKey('services')
          ? ServiceConfig.fromJson(json)
          : ProcessConfig.fromJson(json);
    }

    final kind = rawKind is String ? UnitKind.tryParse(rawKind) : null;
    if (kind == null) throw FormatException('Unknown unit kind: $rawKind');

    return switch (kind) {
      UnitKind.process => ProcessConfig.fromJson(json),
      UnitKind.service => ServiceConfig.fromJson(json),
    };
  }

  /// Parses a JSON value that should be a [DashboardLayout] name.
  ///
  /// Returns [DashboardLayout.list] for missing, non-string, or unknown
  /// values.
  static DashboardLayout _parseDashboardLayout(dynamic value) {
    if (value is String) {
      for (final layout in DashboardLayout.values) {
        if (layout.name == value) return layout;
      }
    }
    return DashboardLayout.list;
  }
}
