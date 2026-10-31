# ADR 005: Native service management (service groups)

**Status:** Accepted; the "A separate page" decision is superseded by
[ADR 006](006-dashboard-units.md) (service groups now share the dashboard card
flow).
**Date:** 2026-10-31

## Context

TrayForge could only manage external **processes**. Controlling Windows
services therefore needed a shell script (`pwsh -File license_svcs.ps1`) that
ran `net start`/`net stop`. The app saw a launcher, not the services: no real
state, no structured failures, and UAC had to be bolted on (`elevated` +
`log_file`, ADR 004). A service is a different kind of thing:

| | Process | Service |
|---|---|---|
| Ownership | TrayForge launched it | the OS owns it |
| State source | exit event | `QueryServiceStatusEx` / `systemctl show` |
| Start/stop | synchronous | request + pending, polled to terminal |
| External change | impossible | someone edits `services.msc` |
| Output | stdout/stderr pipes | none (events only) |
| Privileges | unprivileged | query unprivileged, control escalated |
| Restart on failure | TrayForge's cooldown | the OS recovery policy |

## Decision

Manage **service groups**: one card per group, one OS operation per toggle.

- **A separate module.** `ServiceController` (`lib/services/service_controller.dart`)
  owns the group's aggregate state, the toggle rule (any member up → stop all,
  else start all), poll-to-terminal with a timeout, periodic re-query, failure
  reporting, and the operation log. `ProcessController` gains no service
  branch: mixing both state machines would make the deepest module in the app
  shallow.
- **A real seam.** `ServiceHost` (`lib/foundation/service_host.dart`) is the
  control surface; the Windows SCM (`service_host_win32.dart`) and systemd
  (`service_host_linux.dart`, `systemctl` + `pkexec`) are its adapters, and
  tests use a fake. Operations return per-service results (`ServiceOpResult`)
  instead of throwing, so a partially failed group can still be reported
  honestly.
- **State is read, never persisted.** The OS is the source of truth. Nothing
  is written to a pid file, nothing is restarted by TrayForge, and **nothing is
  stopped on app exit** — the services are not ours.
- **Elevation per operation, not per service.** `ServiceOperator` first asks
  the OS directly; on `accessDenied` it re-runs the whole group in a single
  elevated helper process (Windows: TrayForge's own GUI-subsystem exe in
  `--service-op` mode, so no console flashes; Linux: `pkexec`). Afterwards the
  OS is re-queried — the helper's exit code is never trusted as the outcome.
  Status queries never prompt, so the card's state is always live.
- **Dependencies are reported, not guessed.** A stop blocked by
  `ERROR_DEPENDENT_SERVICES_RUNNING` logs the dependent names whatever
  `stop_dependents` is set to; with `stop_dependents: true` the dependents are
  enumerated and stopped first, inside the same elevated operation, so still
  one prompt.
- **No autostart for groups.** Starting at login would raise a UAC prompt at
  login. Boot behavior belongs to the OS: set the service start type.
- **A separate page.** Service groups live on a Services page reached from the
  Dashboard AppBar instead of being mixed into the process list: two kinds in
  one reorderable list would fork the ordering/reorder semantics for no
  benefit. Unifying both into one ordered `units` array is the documented next
  step if mixed ordering is ever wanted.

## State mapping

| OS state | aggregate |
|---|---|
| stopped / inactive | `stopped` |
| start-pending / activating | `starting` |
| running / paused / active(exited) | `running` |
| stop-pending / deactivating | `stopping` |
| not installed, failed, unreadable, failed operation | `crashed` (sticky until the next operation or an external change) |

## Operation log

Every line of an operation goes to the same output pipeline the processes use:
the services being moved, each member's final state, per-service failures with
the OS error code, the dependent names that block a stop (with an instruction
to enable `stop_dependents`), and the member-level changes the periodic query
notices (`Tomcat: Stopped → Running (changed outside TrayForge)`). Dependents
are enumerated and logged after the operation settles, not from inside the
helper, so the reporting also covers the elevated path. A failed operation pins
`crashed` only until the members actually move again, so an external fix is not
hidden by a stale red card.

## Consequences

- Toggling a group prompts once per operation (unless TrayForge itself runs
  elevated), and the prompt is bounded: the operation phase has its own
  timeout, so a prompt left on screen cannot keep a group busy forever. A
  declined prompt is reported as "cancelled" for the members that needed it —
  not as a silent failure, and not for members that already succeeded.
- The service list becomes config, not a script: `services` in `config.json`
  plus a `service_poll_ms` global (1 s – 1 h).
- `license_svcs.ps1` (and its `elevated`/`log_file` workaround) becomes
  obsolete for service control; `elevated`/`log_file` stay for real process
  launches.
- A resident elevated broker (one consent per session, pipe-relayed output for
  elevated processes too) is the natural follow-up, out of scope here.

## Alternatives rejected

- **A `type: process | service` branch inside `ProcessController`.** Fakes the
  output/pid/wait parts and makes every caller check which half applies.
- **Shelling out to `sc.exe` / `net start`.** Localized text to parse, a
  console flash per operation, no structured error codes.
- **One card per individual service.** The real unit is the group that is
  started/stopped together; per-service rows already communicate detail.
- **Requiring TrayForge to run elevated.** Every managed process would inherit
  elevation, and autostart at login would need a scheduled task.
