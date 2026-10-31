/// Linux adapter for [ServiceHost], implemented on `systemctl`.
///
/// The command path is injectable so the parsing and result mapping are
/// testable without a real systemd: [ServiceCommandRunner] is the seam.
library;

import 'dart:async';
import 'dart:io';

import 'package:trayforge/foundation/service_host.dart';
import 'package:trayforge/foundation/service_status.dart';

/// Runs one command and resolves with its result. Never throws for a non-zero
/// exit code; throws [ProcessException] when the executable is missing.
typedef ServiceCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _defaultRunner(
  String executable,
  List<String> arguments,
) {
  return Process.run(executable, arguments);
}

class LinuxServiceHost implements ServiceHost {
  LinuxServiceHost({ServiceCommandRunner? runner})
    : _run = runner ?? _defaultRunner;

  final ServiceCommandRunner _run;

  @override
  Future<List<ServiceStatus>> query(List<String> names) async {
    final statuses = <ServiceStatus>[];
    for (final name in names) {
      statuses.add(await _queryOne(name));
    }
    return statuses;
  }

  @override
  Future<List<ServiceOpResult>> start(List<String> names) => _act(
    'start',
    names,
    satisfied: (s) => s.state.isUp || s.state == ServiceState.startPending,
  );

  @override
  Future<List<ServiceOpResult>> stop(List<String> names) => _act(
    'stop',
    names,
    satisfied: (s) => s.state.isStopped || s.state == ServiceState.stopPending,
  );

  @override
  Future<List<String>> dependents(String name) async {
    final result = await _run('systemctl', [
      'list-dependencies',
      '--reverse',
      '--plain',
      '--no-legend',
      name,
    ]);
    if (result.exitCode != 0) return const [];
    return [
      for (final line in result.stdout.toString().split('\n'))
        if (line.trim().isNotEmpty && line.trim() != name) line.trim(),
    ];
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  Future<ServiceStatus> _queryOne(String name) async {
    final result = await _run('systemctl', [
      'show',
      '--property=LoadState',
      '--property=ActiveState',
      '--property=SubState',
      name,
    ]);
    if (result.exitCode != 0) {
      return ServiceStatus(name, ServiceState.unknown);
    }

    String? load;
    String? active;
    String? sub;
    for (final line in result.stdout.toString().split('\n')) {
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx);
      final value = line.substring(idx + 1).trim();
      switch (key) {
        case 'LoadState':
          load = value;
        case 'ActiveState':
          active = value;
        case 'SubState':
          sub = value;
      }
    }

    if (load == 'not-found') {
      return ServiceStatus(name, ServiceState.notInstalled);
    }

    switch (active) {
      case 'active':
        // A oneshot unit that finished is `active (exited)`; still up.
        return ServiceStatus(
          name,
          sub == 'paused' ? ServiceState.paused : ServiceState.running,
        );
      case 'activating':
      case 'reloading':
        return ServiceStatus(name, ServiceState.startPending);
      case 'deactivating':
        return ServiceStatus(name, ServiceState.stopPending);
      case 'failed':
        return ServiceStatus(name, ServiceState.failed);
      case 'inactive':
        return ServiceStatus(name, ServiceState.stopped);
      default:
        return ServiceStatus(name, ServiceState.unknown);
    }
  }

  Future<List<ServiceOpResult>> _act(
    String verb,
    List<String> names, {
    required bool Function(ServiceStatus status) satisfied,
  }) async {
    if (names.isEmpty) return const [];

    var result = await _run('systemctl', [verb, '--', ...names]);
    if (result.exitCode == 0) {
      return [for (final name in names) ServiceOpResult.ok(name)];
    }

    var failure = ServiceFailure.unknown;
    var message = _firstLine(result.stderr) ?? _firstLine(result.stdout);

    if (_looksLikeAuthFailure(result)) {
      failure = ServiceFailure.accessDenied;
      final elevated = await _runElevated(verb, names);
      if (elevated != null) {
        if (elevated.exitCode == 0) {
          // The retry succeeded, so the direct attempt's "interactive
          // authentication required" text is stale: a member that is still
          // off target reports just the failure kind.
          message = null;
        } else {
          message = _firstLine(elevated.stderr) ?? message;
          failure = _looksLikeAuthFailure(elevated)
              ? ServiceFailure.accessDenied
              : ServiceFailure.unknown;
        }
      }
    }

    // Always report per-service truth from the OS — never from an exit code,
    // including the elevated one (same rule as the Windows operator).
    final statuses = await query(names);
    return [
      for (final status in statuses)
        satisfied(status)
            ? ServiceOpResult.ok(status.name)
            : ServiceOpResult.failed(status.name, failure, message),
    ];
  }

  /// Retries through `pkexec` for a polkit-authenticated operation.
  Future<ProcessResult?> _runElevated(String verb, List<String> names) async {
    try {
      return await _run('pkexec', ['systemctl', verb, '--', ...names]);
    } on ProcessException {
      return null; // pkexec is not installed.
    }
  }
}

bool _looksLikeAuthFailure(ProcessResult result) {
  final text = '${result.stderr}\n${result.stdout}'.toLowerCase();
  return text.contains('interactive authentication required') ||
      text.contains('access denied') ||
      text.contains('permission denied') ||
      text.contains('authentication is required');
}

String? _firstLine(Object? stream) {
  final line = stream
      ?.toString()
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  return (line == null || line.isEmpty) ? null : line;
}
