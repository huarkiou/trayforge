# Native service management

**Status:** ready-for-agent
**Date:** 2026-10-31

## Problem

TrayForge can only manage external **processes**. Controlling Windows services
therefore needs a shell script (`pwsh -File license_svcs.ps1`) that calls
`net start`/`net stop`, and the app only sees a launcher: no real state, no
structured errors, and a UAC round-trip that had to be bolted on
(`elevated` + `log_file`, ADR 004).

## Solution

Manage service **groups** natively: one card per group, one SCM operation per
toggle, live state from the Service Control Manager, and the existing output
pane as the operation log. Linux uses `systemctl` behind the same seam.

## Design decisions

- **A service is not a process.** `ServiceController` is a separate deep module;
  `ProcessController` gains no service branch (different ownership, state
  source, and failure modes). See ADR 005.
- **The unit is a group** (`services: ["A", "B", ...]`), matching the real use
  case and the existing toggle rule: any member running → stop all; else start
  all. The card shows the aggregate state.
- **State comes from the SCM**, not from a pid file: `query` on an interval
  (configurable, default 5 s) so a change made in `services.msc` shows up.
  No state is persisted; the SCM is the source of truth.
- **Queries never prompt.** Only control operations need admin. On Windows the
  app asks for UAC once per group operation by re-launching its own executable
  in a hidden helper mode (`--service-op …`, one elevated process for the whole
  group), then re-queries the SCM for the authoritative result. Already-elevated
  TrayForge calls the SCM directly (no prompt).
- **Dependencies**: a stop that fails with
  `ERROR_DEPENDENT_SERVICES_RUNNING` logs the dependent service names (and how
  to enable the flag), whatever `stop_dependents` is set to;
  `stop_dependents: true` enumerates the dependents and stops them first, then
  stops the members. Dependents are enumerated after the operation settles, not
  inside the elevated helper, so the report also covers the elevated path.
- **No autostart** for service groups: autostarting at login would raise a UAC
  prompt at login. Boot-time behavior belongs to the SCM (service start type).
- **UI**: a dedicated Services page (cards + detail log + edit page) reached
  from the Dashboard AppBar, not a mixed dashboard. Two kinds in one reorderable
  list would fork the ordering/reorder semantics; the process dashboard stays
  untouched. Unifying into one ordered `units` array is the documented next step
  if mixed ordering is ever needed.
- **`env`, `encoding`, `webui_pattern`, `cwd`, `cleanup_cwd`,
  `delete_before_start`, `max_restarts` do not apply** to a service group.

## State mapping

| SCM state | unit |
|---|---|
| STOPPED | stopped |
| START_PENDING | starting |
| RUNNING / PAUSED / CONTINUE_PENDING | running |
| STOP_PENDING | stopping |
| query error / not installed / failed operation | crashed (logged with the Win32 code; un-pinned when the OS state moves) |

## Testing decisions

- `ServiceHost`/`ServiceOperator` fakes drive `ServiceController` through its
  public interface: aggregate rule, start/stop polling to a terminal state,
  partial failure, dependency error, access-denied → elevated retry, external
  change detection, log lines.
- The Win32 SCM FFI adapter is thin and verified manually (same policy as
  `process_cwd_win32.dart`); the Linux adapter is tested through an injected
  command runner.
- Config round-trip tests for `services` / `service_poll_ms`, including the
  "globals land in three places" trap from the dashboard-layouts spec.

## Out of scope

- One card per individual service (groups only).
- Service start type / recovery policy editing.
- A resident elevated broker (one UAC per session instead of per operation).
- Mixing processes and services in one dashboard list / one ordered `units`
  array.
