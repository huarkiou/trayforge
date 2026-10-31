# trayforge Domain Glossary

Single-context glossary for the trayforge codebase. Terms here name the
concepts the code is organised around; see `docs/adr/` for decisions.

## Unit

One card in the dashboard flow: either a Process or a Service Group. The config
keeps units in one ordered list (`AppConfig.units`, JSON `units` with a `kind`
discriminator), so the dashboard and the tray menu share a single order and a
drag can move any card anywhere. `UnitConfig` is the sealed base of
`ProcessConfig` and `ServiceConfig`; `AppConfig.processes` / `.services` are
derived views of the same list. `UnitKind` is the single place a kind's JSON
value, label and key prefix live. See ADR 006.
_Avoid_: item, entry, item type

## Process

A configured external program trayforge manages. Declared in the config as
a `ProcessConfig` (name, command, cwd, encoding, singleton, autostart,
maxRestarts, webuiPattern, cleanupCwd, deleteBeforeStart, elevated, logFile,
env).

## Elevated launch

A launch with `ProcessConfig.elevated`: on Windows the child is started through
the UAC broker (`ShellExecuteExW` with the `runas` verb), so the user consents
once per launch. The UAC boundary costs the output streams and the built
environment; exit code and termination survive because the broker's process
handle is kept. See ADR 004.

## Service Group

TrayForge's other managed kind: a named set of services (Windows SCM service
names or systemd units) that are started and stopped together. Declared as a
`ServiceConfig` (name, services, stopDependents). The group, not the single
service, is the unit of management: the card shows the aggregate state, the
toggle drives every member to one state, and the detail page lists each member.
The OS owns the state — nothing is persisted and quitting TrayForge never stops
a service. See ADR 005.

## ServiceHost

The service-control seam (`lib/foundation/service_host.dart`): query statuses,
start/stop a list of services, list dependents. Adapters: Windows SCM (FFI) and
systemd (`systemctl`, `pkexec` fallback). Operations return per-service
`ServiceOpResult` values instead of throwing.

## ServiceController

The deep per-group module: aggregate state, toggle rule (any member up → stop
all, else start all), poll-to-terminal after an operation with a timeout,
periodic re-query for external changes, failure reporting, and the operation
log (pushed onto the same output pipeline processes use). A failed operation
pins `crashed`, but the periodic query compares the member states with its own
last snapshot and un-pins it as soon as the members change outside TrayForge,
logging the member-level change (`Tomcat: Stopped → Running (changed outside
TrayForge)`) so a stale red card cannot hide an external fix.

## ServiceManager

The service sibling of [ProcessManager]: materializes one ServiceController per
configured group, applies reload diffs (removing a group disposes the
controller but leaves the services running), owns the per-group streams, and
applies the global `service_poll_ms` interval.

## Elevated helper

On Windows, service control escalates by re-launching TrayForge's own
executable with `--service-op start|stop [--stop-dependents] <name>...`. The
helper runs before Flutter initializes, performs the whole group in one
elevated process (one UAC prompt), and exits with a status code that is only
diagnostic — the caller re-queries the OS for the real result.

## Log tailing

The second output source: when `ProcessConfig.logFile` is set, a
`LogFileTailer` follows that file and feeds appended lines into the same output
pipeline as stdout (ANSI strip, history cap, `webui_pattern`). It starts before
the launch (baseline = current end of file), replays a shrinking file from the
start, and flushes a trailing partial line when the process exits. It is the
only way to see an elevated process's output.

## ProcState

The lifecycle state of a Process: `stopped`, `starting`, `running`,
`stopping`, `crashed`, `cooldown`.

## ProcessController

The deep per-process module owning a Process's full lifecycle: the state
machine, launch sequence (shlex, env, cwd-relative exe resolution,
singleton guards, cleanupCwd, deleteBeforeStart), kill-tree stop, crash
restart + cooldown, pid file, output wiring, and its streams. One instance
per configured Process.

Interface decisions (ADR-worthy, recorded here as agreed):

- **Config is a parameter, never read from disk.** `start(appConfig,
  procConfig)` / `toggle(appConfig, procConfig)` receive the resolved
  `AppConfig` (global pipeline limits) and `ProcessConfig` from the
  coordinator; the controller holds no `ConfigStore`.
- **`toggle` owns the start/stop decision** (active → stop, terminal →
  start). Viewmodels call it instead of re-deciding.
- **`applyRemoval` is immediate**: set the manual-stop flag (so the exit
  handler doesn't restart), kill the handle if alive, delete the pid file,
  dispose. Idempotent in any state. The launch sequence checks a `removed`
  flag before each side-effecting step so an in-flight `start` can't
  resurrect pid files or touch a disposed pipeline.
- **`stop` during `starting` is pending-stop**: a no-op there would let
  the launch sequence finish and end up `running` despite the user's
  stop. `stop()` sets a pending-stop flag; the launch sequence checks it
  right after obtaining the handle and kills immediately. Same mechanism
  as `removed`.
- **`stop` during `cooldown` cancels the scheduled restart**: nothing is
  running, but the pending auto-restart is the only thing that could
  start the process again — it is cancelled and the state becomes
  `stopped`. A stale exit or stop continuation never clobbers a
  replacement launch: the exit handler and the stop continuation both
  guard on the handle being the current one (`_handle != handle` is
  ignored only when the handle is already null, i.e. cleaned up).
- **Dispose is safe against late continuations**: `_setState` and system
  messages guard on closed controllers/disposed pipeline, so an in-flight
  `stop()` continuation or exit handler can't throw after `applyRemoval`
  disposed the controller.
- Streams (`output`, `webUi`, `state`) are owned by the controller;
  `getState` reports `stopped` for unknown names.

## ProcessManager

The coordinator module: holds the name→ProcessController map
(materialized for every configured Process on init/reload, **diff-based**
— only removed names are disposed, only new names created; kept names
keep their live streams), applies config reload diffs (removals via
`controller.applyRemoval`), runs autostart, scans stale pid files at
init, and exposes the single facade viewmodels talk to. Its per-process
methods delegate to controllers; `cooldownDuration` and `flushNow` stay
on the facade as forwarding seams for existing tests. Materialization
happens **before** `onConfigReloaded` is emitted, so viewmodels always
subscribe to real streams.

## UI

**Dashboard**:
The main window showing every configured Unit at a glance — processes and
service groups in one ordered card flow.
_Avoid_: main window, home screen

**List layout**:
The default Dashboard arrangement — wide cards, each with a status dot,
controls, and (for a Process) an output preview or (for a Service Group) its
members; reordered by long-press.
_Avoid_: card list, the current layout

**Grid layout**:
The alternative Dashboard arrangement — square compact cards without an
output preview, arranged in an adaptive grid, reordered by long-press.
_Avoid_: tile view, square card matrix

**Detail page**:
The full-screen view opened by tapping a Process or Service Group card — the
complete output log or operation log, status, and controls.
_Avoid_: log page, process viewer

**Follow-latest**:
The log-view state where the view tracks the newest output: while the
scroll position is within the Follow threshold of the bottom, arriving
output scrolls the view to the bottom.
_Avoid_: auto-scroll, sticky bottom

**Detached**:
The log-view state after the user scrolls beyond the Follow threshold:
arriving output appends without changing the visible content. Scrolling
back within the threshold returns to Follow-latest.
_Avoid_: scroll-lock, frozen, pinned

**Follow threshold**:
The fixed distance from the bottom of the log (100 px) that separates
Follow-latest from Detached.
_Avoid_: autoscroll threshold

Log-view behaviour (as agreed):

- Opening the Detail page always starts in Follow-latest, pinned to the
  newest output, before any user scrolling.
- Clearing the output returns the view to Follow-latest: the previous
  scroll position referred to content that no longer exists.
- Head trimming at the output-history cap may shift Detached content;
  accepted as orthogonal to Follow-latest/Detached.
