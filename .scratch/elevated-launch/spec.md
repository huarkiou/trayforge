# Per-process elevated launch (Windows UAC)

One-off scripts that need administrator rights (service start/stop, for
example) could not be managed from TrayForge without losing all feedback:

- the script's own `Start-Process -Verb RunAs` makes the tracked process a
  short-lived launcher — the card returns to a terminal state at once;
- the elevated child's output goes to its own console, never to the output
  pane;
- a clean hand-off (exit code 0) was reported as **Crashed**;
- and with `singleton: false`, the OS-level singleton check could still refuse
  to launch `pwsh.exe -File script.ps1` whenever any other `pwsh.exe` was
  alive.

## Scope

- `ProcessConfig.elevated` (config key `elevated`, default `false`) and a
  matching **Elevated (UAC)** checkbox in the process edit page.
- Windows launch through the UAC broker: `ShellExecuteExW` + `runas`, with the
  returned process handle used for exit code and termination.
- `ProcessConfig.logFile` (config key `log_file`) with a **Log File** field in
  the edit page: tail a file the process appends to into the output pane. This
  is how an elevated process produces visible output at all, and it works for
  ordinary processes too.
- System messages that say what the UAC boundary costs (no stdout/stderr, no
  `env`) and what is being tailed.
- OS-level singleton check gated on `singleton: true`.
- Exit code 0 → `stopped`, not `crashed`.

Out of scope (documented in ADR 004): capturing the elevated process's own
stdout/stderr, passing the built environment to an elevated child, stopping
elevated processes without the broker handle, and killing an elevated
process's own children.

## Issues

- `issues/01-process-elevated-launch.md` — the feature, its supporting fixes,
  and the verification done.
