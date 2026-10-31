/// Localized display labels for the domain state enums.
///
/// The enums keep their English `label` getters: the process and service
/// controllers append those to the output log, which is a console-style
/// transcript and deliberately stays in English. Everything the user reads as
/// chrome — cards, detail pages, the tray — goes through these extensions.
library;

import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/service_status.dart';
import 'package:trayforge/l10n/app_localizations.dart';

/// Localized label for a process state.
extension ProcStateL10n on ProcState {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ProcState.stopped => l10n.stateStopped,
    ProcState.starting => l10n.stateStarting,
    ProcState.running => l10n.stateRunning,
    ProcState.stopping => l10n.stateStopping,
    ProcState.crashed => l10n.stateCrashed,
    ProcState.cooldown => l10n.stateCooldown,
  };
}

/// Localized label for a single service's state.
///
/// The states shared with [ProcState] reuse the same words (stopped, starting,
/// running, stopping); the service-specific ones have their own messages.
extension ServiceStateL10n on ServiceState {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    ServiceState.notInstalled => l10n.serviceStateNotInstalled,
    ServiceState.stopped => l10n.stateStopped,
    ServiceState.startPending => l10n.stateStarting,
    ServiceState.running => l10n.stateRunning,
    ServiceState.stopPending => l10n.stateStopping,
    ServiceState.paused => l10n.serviceStatePaused,
    ServiceState.failed => l10n.serviceStateFailed,
    ServiceState.unknown => l10n.serviceStateUnknown,
  };
}

/// Localized label for a unit kind, used in validation messages.
extension UnitKindL10n on UnitKind {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    UnitKind.process => l10n.kindProcess,
    UnitKind.service => l10n.kindServiceGroup,
  };
}
