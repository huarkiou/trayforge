# Inherit TrayForge's elevated token for elevated launches

Status: resolved
Type: task

## Problem

`elevated: true` always went through the UAC broker, even when TrayForge
itself had been started elevated. In that deployment the broker still gives
the child a fresh console, so every console launch flashed a window and its
stdout/stderr never reached the output pane; `env` was dropped as well. Those
costs only exist while TrayForge is unprivileged — an elevated TrayForge can
create the child with its own administrator token instead.

## Work

1. `lib/foundation/process_elevation_win32.dart`: `isCurrentProcessElevated`
   via `GetTokenInformation(TokenElevation)`, not `IsUserAnAdmin` or group
   membership (a UAC-filtered administrator token is a member but is neither
   elevated nor able to start an administrator child).
2. `RealProcessRunner.startElevated`: when the probe says elevated, delegate
   to the plain `start` — inherited administrator token, pipes, `env`, no
   prompt, no console window, tree kill. A failed probe falls back to the
   broker path; the answer is not cached, so a transient failure can recover
   on the next launch.
3. `LaunchKind` on `IProcessHandle` (`direct` / `uacBroker`) names the launch
   route: one concept drives pipe wiring, the mode message, and the kill
   mechanism.
4. `ProcessController`: passes the built environment to elevated launches,
   states the inherited-token mode, and reports a failed kill of an elevated
   child instead of swallowing it.
5. Docs: README, CONTEXT, `ProcessConfig` comments, edit-page help, and the
   ADR 004 amendment that scopes the original broker-only consequences.

## Verification

- `dart format lib test` — no changes; `dart analyze lib test` — no new
  findings (16 pre-existing infos in untouched files).
- `flutter test` — 446 passing. New coverage: both elevated launch routes,
  env pass-through, output capture, tree kill vs broker-handle kill, kill
  failure reporting, probe-exception and broker fallbacks, and a `whoami`
  integrity-SID cross-check for `TokenElevation`.
- Not run: a live elevated-TrayForge session, which needs a human UAC
  consent. The inherited-token path is exercised at the runner and controller
  seams with the injected probe.

## Comments

- 2026-10-31: Two review rounds (standards + spec). Fixed the stale
  unconditional claims in README/CONTEXT/models/edit page, scoped the ADR 004
  Decision bullets, replaced the output-only handle flag with `LaunchKind`,
  fixed the kill result handling, corrected the `CREATE_NO_WINDOW` citation,
  removed probe caching, and strengthened the FFI and broker-path tests.
  Accepted as a judgement call: the two Win32 adapters keep their own
  `DynamicLibrary`/`CloseHandle` boilerplate rather than sharing a binding
  helper.
