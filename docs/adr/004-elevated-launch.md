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

Consequences accepted:

- **The UAC prompt is owned by TrayForge**, once per launch (crash-restarts
  prompt again, as they must).
- **No direct output capture.** The broker creates the elevated child with a
  fresh console instead of inheriting TrayForge's stdout/stderr pipes, so the
  process's own stdout never reaches the output pane. A system message states
  this at start time.
- **`log_file` is the output channel that survives.** A process may append to
  a file TrayForge tails (`lib/foundation/log_file_tailer.dart`); appended
  lines go through the same pipeline as stdout (ANSI strip, history cap,
  `webui_pattern`). This is a generic second output source, not an
  elevated-only hack: it also serves daemons that already log to a file.
  Tailing starts before the launch and snapshots the end of file, so a
  restart does not replay the backlog; a shrinking file (truncated/recreated)
  is replayed from the start.
- **`env` is not applied.** `ShellExecuteEx` takes no environment block.
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
