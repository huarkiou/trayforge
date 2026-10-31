# Per-process `elevated` launch flag

Status: resolved
Type: task

## Problem

Launching `D:\Apps\cli_tools\myscripts\license_svcs.ps1` from TrayForge
(`pwsh.exe -File license_svcs.ps1`, `singleton: false`) never produced a usable
admin run:

- the script self-elevates with `Start-Process -Verb RunAs` and exits, so
  TrayForge only tracked the launcher;
- the elevated PowerShell's output never reached the output pane;
- the launcher's exit code 0 was surfaced as **Crashed**;
- when another `pwsh.exe` was alive, the launch was refused outright with
  "Process is already running at OS level", despite `singleton: false`.

The requested shape was a per-process switch for whether TrayForge should ask
for UAC.

## Work

1. `ProcessConfig.elevated` — model, `toJson`/`fromJson`/`copyWith`, README
   field table, ADR 004.
2. `ShellExecuteExW`/`runas` launcher in
   `lib/foundation/elevated_process_win32.dart`: `SEE_MASK_NOCLOSEPROCESS`,
   `GetProcessId`, polled `GetExitCodeProcess`, `TerminateProcess`,
   `Win32` error mapping (including "UAC elevation was cancelled").
3. `IProcessRunner.startElevated` + `ElevatedProcessHandle` (empty output
   streams, handle-based kill).
4. `ProcessController`: elevated branch in the launch sequence, "no output"
   system message, `_killHandle` (handle kill for elevated, tree kill
   otherwise).
5. OS-level singleton check now runs only for `singleton: true`.
6. Exit code 0 → `stopped` with "Process exited (code 0)".
7. Edit page checkbox **Elevated (UAC)**.
8. `ProcessConfig.logFile` + `LogFileTailer` (`lib/foundation/log_file_tailer.dart`):
   appended lines flow into the output pipeline (ANSI strip, history cap,
   `webui_pattern`). Started before the launch so the baseline is the
   pre-launch end of file; shrinking file replayed; trailing partial line
   flushed on exit. Edit page field **Log File**.
9. Exit-report ordering: the tailer's final read and the pipeline flush happen
   before the "Process exited" message, so a one-shot log reads in order.
10. Tests: quoting, model round-trip (including `log_file`), elevated
    launch/cancel/stop, singleton gating, clean exit, tailer semantics, and
    log-file wiring through the controller.

## Verification

- `dart format lib test` / `dart analyze lib test` — clean apart from
  pre-existing infos.
- `flutter test` — 313 passing.
- Live (real UAC, accepted each time):
  - elevated `cmd.exe` tracked with its PID; `stop` terminated it through the
    broker handle;
  - elevated `exit 5` → "Process exited with code 5" + `crashed`;
    elevated `exit 0` → "Process exited (code 0)" + `stopped`;
  - a script with **no self-elevation** (`pwsh.exe -File svcs_probe.ps1`)
    launched with `elevated: true` reported `elevated=True` inside the script;
  - `license_svcs.ps1 -Action status` launched elevated with
    `log_file: license_svcs.log`: the output pane received
    `[trayforge] Tailing log file: …`, the script's status lines, and
    `[trayforge] Process exited (code 0)`.
- `license_svcs.ps1` rewritten: self-elevation removed (TrayForge owns UAC),
  every line appended to `license_svcs.log` as UTF-8 (no BOM), native `net`
  output decoded with the OEM code page, per-service result judged by the
  resulting service state rather than `net.exe`'s exit code, and a non-admin
  start/stop exits 5 with an explanatory log line.
