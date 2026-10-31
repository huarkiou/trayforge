# Native service management

Status: resolved
Type: task

## Problem

Managing Windows services needed a shell script plus `elevated`/`log_file`
workarounds (ADR 004): TrayForge tracked a launcher, not the services, and had
no real state, structured errors, or way to notice external changes.

## Work

1. `ServiceHost` seam + adapters: Windows SCM via FFI
   (`service_host_win32.dart`: `OpenSCManagerW`/`OpenServiceW`/
   `QueryServiceStatusEx`/`StartServiceW`/`ControlService`/
   `EnumDependentServicesW`) and systemd (`service_host_linux.dart`:
   `systemctl show`, `start`/`stop`, `list-dependencies`, `pkexec` fallback).
   Per-service results instead of exceptions.
2. `ServiceOperator`: direct attempt, elevate the whole group on
   `accessDenied` (`--service-op` helper mode in TrayForge's own exe, one UAC
   per operation), then re-query the OS as the authoritative result.
   `performServiceOp` is shared by the direct and elevated paths, including
   `stop_dependents` (dependents enumerated and stopped first, before the
   members).
3. `ServiceController`: aggregate state, toggle rule, poll-to-terminal with a
   timeout, periodic re-query with member-level external-change logging (which
   also un-pins a `crashed` left by a failed operation), operation log on the
   existing output pipeline.
4. `ServiceManager`: materialize/reload diffing, facade (state/output/statuses
   streams, toggle, refresh, poll interval), no persistence and no stop on
   exit.
5. Config: `ServiceConfig` (`name`, `services`, `stop_dependents`),
   `AppConfig.services`, `service_poll_ms` global (default 5000, clamped
   1s–1h), `ConfigStore.validateService`; both settings save paths carry the
   lists (the "a new global lands in three places" trap).
6. UI: Services page (group cards with per-service rows), group detail page
   with the operation log, add/edit form, Dashboard AppBar entry, Settings
   field for the poll interval.
7. `main`: helper mode before Flutter initialization; `ServiceManager` wired
   into DI, dashboard and settings view models.

## Verification

- `dart format` / `dart analyze` clean apart from pre-existing infos;
  `flutter test` 372 passing (new: state mapping, Linux command mapping and
  `pkexec` fallback, operator elevation/verification/cancellation/dependents,
  controller toggle/timeout/external-change/config-update, manager
  reload/removal, config round-trip, services page widget tests).
- Live, on this machine: SCM queries against the four SIMULIA/ANSYS services
  (real FFI, no prompt), and control operations through the elevated helper
  (real UAC) against a harmless service, restoring its original state.

## Review pass (two-axis review of the commit)

Standards: no hard violations; the duplication and dead-surface findings were
fixed — `ServiceOpKind.reaches` replaces two copies of the reached-state rule,
one Win32 error table replaces the double switch, `_control` replaces
`_startOne`/`_stopOne`, `_applyConfig` replaces the duplicated manager
bookkeeping, `ConfigStore._validateName` replaces the duplicated name checks,
`ServiceStatusRow` and `FollowLatestController` replace the duplicated row
rendering and follow-latest scroll logic, and the unused surface
(`ServiceViewModel.refresh`, `ServiceManager.refresh/isBusy`,
`LinuxServiceHost.allowElevation`, `ParsedServiceOp`,
`ServiceElevationException`) is gone.

Spec: the gaps found were closed —
- dependent service names are logged when a stop is blocked, whatever
  `stop_dependents` is set to (the names are resolved after the operation
  settles, so this also covers the elevated path; and the Win32 code is logged
  for problem states, so `win32ExitCode` is read);
- `stop_dependents` enumerates and stops the dependents first, before the
  members, not the other way round;
- the settings field reaches the documented 1 h maximum;
- the toggle button reflects the toggle rule (statuses) instead of
  `ProcState.isActive`, so a crashed group with a running member offers "Stop";
- Win32 `OpenServiceW` failures are only "not installed" for
  `ERROR_SERVICE_DOES_NOT_EXIST`;
- a failed operation's `crashed` is un-pinned by an external change, and
  member-level changes are logged, not just aggregate ones;
- a declined UAC reports `cancelled` only for the members that needed
  elevation;
- the Linux host re-queries after `pkexec` instead of trusting its exit code;
- the operation phase (including a pending UAC prompt) is bounded by
  `operationTimeout` (`settleTimeout` bounds only the poll-to-terminal phase).

While verifying those fixes, a latent Win32 bug surfaced that the review could
not see: every binding was resolved with `lookupFunction` per call, and
resolving/first-calling a function pointer clears the thread's last error in
Dart's FFI. `GetLastError()` therefore always read 0, so **an access-denied
control call was classified as `unknown` and the elevator was never
triggered** — and a declined UAC prompt in `elevated_process_win32` read as
"the shell returned no error code". Both modules now resolve their bindings
once and warm `GetLastError` before the first call that can fail; live checks
confirm `accessDenied (Win32 error 5)` for a non-elevated start,
`Not installed` for a missing service, and an accurate message for a missing
executable.

## Second review pass (review of the fixes themselves)

Reviewing the fix delta found the fixes were incomplete in places; all closed:
- the existence check in `launchElevated` threw after allocating four native
  buffers (leak) and resolved relative paths against TrayForge's cwd instead of
  `workingDirectory`; it now runs before any allocation, resolves against the
  working directory, and distinguishes a directory from a missing file;
- `LinuxServiceHost.allowElevation` was still declared; the stale
  "interactive authentication required" text is cleared when the `pkexec` retry
  succeeds;
- `stop_dependents` was still stop-then-retry while the docs said
  dependents-first; `performServiceOp` now enumerates and stops the dependents
  first (deduped, group members skipped), with no retry;
- dependent-name reporting no longer depends on the operator's failure kind
  (which the elevated path does not produce): after the settle phase every
  member a stop left up is queried once and reported;
- the crashed un-pin compares a member-state snapshot, so an aggregate that is
  `crashed` on both sides still un-pins, and a recovered query no longer logs a
  spurious "changed outside TrayForge";
- the timeouts are named for what they bound (`settleTimeout` /
  `operationTimeout`), and a timed-out operation keeps an in-flight guard so a
  late UAC consent cannot race a second helper;
- `ServiceViewModel.isUp` reuses `anyServiceUp`, the unused
  `FollowLatestController.isFollowing` is gone, `ServiceStatusRow` restores the
  selectable detail-page name and its explicit label style, the settings
  steppers clamp to min/max, and CONTEXT.md/ADR/spec wording now matches the
  code.



