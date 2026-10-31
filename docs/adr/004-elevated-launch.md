# ADR 004: Per-process elevated launch (Windows UAC)

**Status:** Accepted
**Date:** 2026-10-31

## Context

TrayForge could only launch processes as the unprivileged user running the
tray. One-off scripts that need admin rights (starting/stopping services, for
example) therefore had to self-elevate:

```powershell
Start-Process -FilePath powershell -ArgumentList "-File `"$PSCommandPath`"" -Verb RunAs
exit
```

That works at the OS level, but TrayForge loses sight of the work:

- the tracked process is the short-lived **launcher**, so the card returns to a
  terminal state immediately;
- the elevated child's output never reaches the output pane — the console it
  prints to is not TrayForge's pipe;
- a clean hand-off (exit code 0) was reported as **Crashed**.

Asking the user to keep writing this pattern also means every script invents its
own elevation, and nothing in the UI says a process needs admin.

## Decision

Add a per-process `elevated` flag. When set, `ProcessController` launches the
command through `IProcessRunner.startElevated`, which on Windows calls
`ShellExecuteExW` with the `runas` verb
(`lib/foundation/elevated_process_win32.dart`).

Consequences accepted while TrayForge itself is unprivileged (see the amendment
at the end of this ADR for an elevated TrayForge):

- **The UAC prompt is owned by TrayForge**, once per launch (crash-restarts
  prompt again, as they must).
- **No direct output capture (unless TrayForge itself is elevated).** The
  broker creates the elevated child with a fresh console instead of inheriting
  TrayForge's stdout/stderr pipes, so the process's own stdout never reaches
  the output pane. A system message states this at start time.
- **`log_file` is the output channel that survives.** A process may append to
  a file TrayForge tails (`lib/foundation/log_file_tailer.dart`); appended
  lines go through the same pipeline as stdout (ANSI strip, history cap,
  `webui_pattern`). This is a generic second output source, not an
  elevated-only hack: it also serves daemons that already log to a file.
  Tailing starts before the launch and snapshots the end of file, so a
  restart does not replay the backlog; a shrinking file (truncated/recreated)
  is replayed from the start.
- **`env` is not applied (unless TrayForge itself is elevated).**
  `ShellExecuteEx` takes no environment block.
- **Exit code and stop work.** `SEE_MASK_NOCLOSEPROCESS` returns the process
  handle: `GetExitCodeProcess` (polled) feeds the normal exit path, and
  `TerminateProcess` stops the process without spawning an elevated
  `taskkill` (which a non-elevated tray cannot do). Only that process is
  terminated — children it spawned itself are elevated too and survive a
  non-elevated kill.
- **`cleanup_cwd` / pid-start-time checks cannot inspect elevated processes**:
  reading their PEB needs `PROCESS_VM_READ`, which a non-elevated tray does not
  have. They are skipped silently, as with other inaccessible pids.

Two supporting fixes came out of the same investigation and are kept separate
from the flag:

- the **OS-level singleton check** now runs only for `singleton: true`
  processes; before, a `singleton: false` one-off script was refused whenever
  another instance of its interpreter (`pwsh.exe`, `python.exe`, …) was alive;
- an **exit code of 0** lands on `stopped` instead of `crashed`, so a
  successfully finished one-shot command is not reported as a failure.

## Alternatives considered

- **Elevate the whole TrayForge process.** Every managed process would then run
  as admin, the tray would prompt at login, and autostart at login would need a
  scheduled task. Too blunt for one or two processes.
- **Relay output through a named pipe.** Possible (the elevated child connects
  back to a pipe the tray serves), but it requires a cooperating launcher in
  every elevated command and a temporary IPC surface. Not worth it for the
  current use case; `log_file` gives the same visibility with no IPC.
- **Have TrayForge itself wrap the command and redirect its output to a managed
  file.** Works without touching the command, but the wrapper becomes the
  tracked process (tree-kill and exit-code semantics get murkier) and native
  output gets decoded with the console code page on the way through, which
  mangles non-ASCII localized messages. `log_file` keeps encoding under the
  producer's control.
- **Keep self-elevation and only fix the reporting.** Leaves every user writing
  the same `Start-Process -Verb RunAs` boilerplate, and still cannot report the
  exit code of the elevated work.

## Amendment (2026-10-31): TrayForge itself running elevated

The decision above assumes an **unprivileged** TrayForge. There the broker is
the only way to obtain administrator rights, and the output/`env` loss is the
price of crossing the UAC boundary.

That price belongs to the broker, not to `elevated`. A TrayForge process that
already holds an elevated token can start an elevated child with a plain
`CreateProcess`: the child inherits the administrator token, AppInfo is never
involved, so there is no consent prompt, and the stdout/stderr pipes and the
built environment block keep working. There is no console window either —
`dart:io`'s normal (piped) start mode includes `CREATE_NO_WINDOW`; only its
`inheritStdio` mode omits the flag, and TrayForge never uses that mode
(dart-lang/sdk `b6c5e52`, refined by `8a43a89`, issue `#39945`). The child
stays at TrayForge's integrity level.

`RealProcessRunner.startElevated` therefore probes the current token
(`lib/foundation/process_elevation_win32.dart`,
`GetTokenInformation(TokenElevation)`) on each elevated launch and delegates
to the normal `start` when it is elevated. The answer is not cached: two Win32
calls per launch cost nothing, and caching a failed query would permanently
demote an elevated TrayForge to the prompting path. A failed probe is not a
launch failure either — it falls back to the broker path, which still elevates
and merely prompts. Consequences:

- **No prompt, output captured, `env` applied** for `elevated: true` while
  TrayForge runs elevated. The returned handle reports
  `IProcessHandle.launchKind`, so `ProcessController` wires the pipes, states
  the mode in a system message, and tree-kills it. `log_file` stays a generic
  second output source rather than the only channel.
- **The flag grants no extra privilege in that mode.** Every child inherits
  TrayForge's administrator token, including processes without `elevated`.
  That global trade-off is exactly why elevating the whole app is still not
  the default; this amendment only makes an already-elevated deployment
  coherent.
- **Kill uses the tree kill.** Both sides are on the same side of the UAC
  boundary, so `taskkill /t /f` is allowed and also reaps the children;
  terminating only the broker's direct child remains the broker-handle path.
- **Detection must use `TokenElevation`**, not `IsUserAnAdmin` or group
  membership: an administrator running with UAC's filtered token is neither
  elevated nor able to start a child that requires administrator rights
  (`CreateProcess` fails with `ERROR_ELEVATION_REQUIRED`, 740). A failed token
  query falls back to the broker path, which is safe: it still elevates, it
  just prompts.
- A child cannot exceed TrayForge's integrity level (no
  System/TrustedInstaller child), `CREATE_NO_WINDOW` only suppresses the
  automatically created console, and the broker-path caveats above still apply
  whenever TrayForge is unprivileged.
