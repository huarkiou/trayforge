# TrayForge

[![Test](https://github.com/huarkiou/trayforge/actions/workflows/test.yml/badge.svg)](https://github.com/huarkiou/trayforge/actions/workflows/test.yml)

A Flutter desktop app that manages background processes and service groups from
the system tray. Define them in a JSON config, and TrayForge keeps them running —
auto-start, auto-restart on crash, and colour-coded tray icon at a glance.

## Features

- **System tray icon** — green when all processes are running, yellow when partially
  running, red when none are. Single-click the tray icon to toggle the management
  window; right-click for the context menu.
- **Start / stop processes** from the tray menu or the dashboard.
- **Dashboard layouts** — switch between a list of wide cards and a grid of
  compact square cards from the dashboard AppBar; reorder cards by long-press
  drag in either layout.
- **Inline editing** — add, edit, duplicate, delete, and reorder units directly
  from the Dashboard — no need to open Settings.
- **Auto-start** — processes with `autostart: true` launch when TrayForge starts.
- **Crash recovery** — configurable `max_restarts` with cooldown periods. Gives up
  after the limit and marks the process as crashed.
- **Output viewer** — merged stdout + stderr with ANSI-stripping, per-process
  scrollable output, and copy-to-clipboard.
- **Follow-latest log view** — the detail page tracks the newest output and
  scrolls along with it; scrolling up detaches the view, and scrolling back down
  resumes following.
- **WebUI detection** — set a `webui_pattern` regex and TrayForge captures the URL
  when your process prints it. Copy it from the process detail page.
- **Singleton enforcement** — prevent duplicate process instances (per-process or
  OS-level).
- **Working directory cleanup** — `cleanup_cwd` kills residual processes from the
  same working directory before starting a new instance.
- **Elevated launch (UAC)** — mark a process `elevated: true` and TrayForge
  launches it through the Windows UAC broker; the exit code still reaches the
  dashboard.
- **Log-file tailing** — set `log_file` and lines the process appends to that
  file show up in the output pane. This is how elevated processes surface
  output at all.
- **Native service groups** — manage Windows services (or systemd units) directly:
  live state from the OS, one UAC prompt per start/stop of the whole group,
  structured errors, no shell script in between. See
  [ADR 005](docs/adr/005-native-service-management.md).
- **One card flow for both kinds** — processes and service groups share the
  Dashboard: one ordered `units` list in `config.json`, one drag to reorder, one
  `+` menu to add either. See [ADR 006](docs/adr/006-dashboard-units.md).
- **Config hot-reload** — the tray's **Reload Settings** item (or the Settings
  page button) re-reads `config.json` and applies process **and** service
  changes without restarting the app.
- **Delete-before-start** — delete lock/persistent files before launching.
- **Single-instance app** — only one TrayForge runs at a time; starting a second
  instance brings the existing one to the foreground.
- **Corrupted config recovery** — detects corrupted `config.json`, backs it up, and
  alerts you instead of crashing.
- **Cross-platform** — Windows and Linux.

## Screenshots

**List layout** — wide cards with status, controls, and an output preview.

![Dashboard in list layout](docs/screenshots/dashboard-list.png)

**Grid layout** — compact square cards with the latest five output lines.

![Dashboard in grid layout](docs/screenshots/dashboard-grid.png)

**Detail page** — full output log with status and controls.

![Process detail page](docs/screenshots/detail-page.png)

## Configuration

TrayForge stores its config in `config.json` under the app data directory
（`%APPDATA%/trayforge/` on Windows, `~/.local/share/trayforge/` on Linux）.

### Example `config.json`

Processes and service groups share one ordered `units` array: the order in the
file is the order of the cards on the Dashboard, and `kind` says which is which.

```json
{
  "output_history_limit": 1000,
  "output_refresh_ms": 500,
  "dashboard_layout": "list",
  "units": [
    {
      "kind": "process",
      "name": "NapCat",
      "cwd": "C:\\NapCat",
      "cmd": "napcat.exe",
      "singleton": true,
      "autostart": true,
      "webui_pattern": "WebUI started at (http://[\\d.:]+)",
      "max_restarts": 3
    },
    {
      "kind": "service",
      "name": "Licenses",
      "services": ["SIMULIA FLEXnet License Manager", "ANSYSLicensingTomcat"],
      "stop_dependents": false
    },
    {
      "kind": "process",
      "name": "Redis",
      "cwd": "C:\\Redis",
      "cmd": "redis-server.exe",
      "singleton": true,
      "autostart": true,
      "cleanup_cwd": true,
      "delete_before_start": ["dump.rdb"]
    }
  ]
}
```

A config written by an older version (`processes` and `services` as two arrays,
no `units`) still loads: it is read as "processes first, then service groups",
and the next save rewrites it as `units`.

### Process fields

| Field                  | Type              | Description                                                                                        |
|------------------------|-------------------|----------------------------------------------------------------------------------------------------|
| `name`                 | `string`          | Display name. Must not contain `/` or `\`.                                                         |
| `cmd`                  | `string`          | Shell command to run. Split with shlex rules（quotes, escapes）.                                   |
| `cwd`                  | `string?`         | Working directory. Relative executables in `cmd` are resolved against this.                          |
| `autostart`            | `bool`            | Start this process when TrayForge launches.                                                        |
| `singleton`            | `bool`            | Prevent launching a second copy while one is running.                                              |
| `max_restarts`         | `int?`            | Max crash restarts before giving up. Cooldown between restarts is 60 seconds.                      |
| `webui_pattern`        | `string?`         | Regex to detect a Web UI URL in stdout/stderr. First capture group is the URL.                     |
| `cleanup_cwd`          | `bool`            | Kill residual processes from the same working directory before starting（uses FFI on Windows）.     |
| `delete_before_start`  | `string[]`        | Delete these files (relative to `cwd`) before launching. Path-escape safe.                         |
| `env`                  | `object?`         | Extra environment variables（merged on top of system env）.                                       |
| `encoding`             | `string?`         | Process output encoding. Defaults to UTF-8.                                                        |
| `elevated`             | `bool`            | Launch elevated（Windows UAC prompt）. stdout/stderr is not captured and `env` is not applied.       |
| `log_file`             | `string?`         | Tail this file into the output pane（relative to `cwd`）. Appended lines only.                      |

### Elevated processes (Windows)

`elevated: true` starts the process through the UAC broker
(`ShellExecuteEx` with the `runas` verb), so Windows shows a consent prompt.
Exit code and stop still work — TrayForge keeps the broker's process handle.

Two limits are inherent to UAC:

- **No stdout/stderr.** An elevated child gets its own console instead of
  TrayForge's pipes. Set `log_file` and have the process append to that file —
  TrayForge tails it into the output pane, which is the only way to see what an
  elevated process did.
- **No `env`.** `ShellExecuteEx` cannot pass an environment block; the child
  sees the environment Windows gives an elevated process.

Each launch (including a crash-restart) prompts again. A script that
self-elevates (`Start-Process -Verb RunAs`) does not need this flag — but
TrayForge then tracks the short-lived launcher, not the elevated child, and
loses the exit code.

### Log-file tailing

`log_file` turns a file into a second output channel:

- Relative paths resolve against `cwd`.
- Only lines appended **after** the launch are shown — starting a long-running
  daemon does not replay its backlog. A file that shrinks (truncated or
  recreated by the process) is replayed from the beginning.
- Lines go through the usual pipeline: ANSI stripping, history cap, and
  `webui_pattern` detection all apply.
- A trailing line without its newline is emitted when the process exits.

### App-level fields

| Field                  | Type    | Default  | Description                                   |
|------------------------|---------|----------|-----------------------------------------------|
| `output_history_limit` | `int`    | `1000`   | Max output lines buffered per process.           |
| `output_refresh_ms`    | `int`    | `500`    | Interval (ms) for batching output line flushes.  |
| `service_poll_ms`      | `int`    | `5000`   | How often service groups re-query the OS (1 s – 1 h). |
| `dashboard_layout`     | `string` | `list`   | Dashboard arrangement: `list` (wide cards) or `grid` (compact square cards). |

### Service groups

A service group is a unit with `"kind": "service"`. It is a card in the same
Dashboard flow as the processes: started or stopped as one unit, showing the
aggregate state plus every member's own state.

```json
{
  "kind": "service",
  "name": "Licenses",
  "services": [
    "SIMULIA FLEXnet License Manager",
    "ANSYSLicensingTomcat"
  ],
  "stop_dependents": false
}
```

| Field             | Type       | Description                                                       |
|-------------------|------------|-------------------------------------------------------------------|
| `name`            | `string`   | Display name of the group. Must not contain `/` or `\`.            |
| `services`        | `string[]` | Windows service names (or systemd units), managed together.        |
| `stop_dependents` | `bool`     | Stop dependent services first when a stop is blocked by them.      |

Behavior worth knowing:

- **The OS owns the state.** TrayForge queries it every `service_poll_ms` and
  logs external changes, so a service started from `services.msc` shows up.
  Nothing is remembered, nothing is restarted, and quitting TrayForge never
  stops a service.
- **Queries never prompt; control does.** A start/stop needs administrator
  rights and asks for them once for the whole group (a declined prompt is
  reported as cancelled). If TrayForge itself runs elevated, no prompt appears.
- **Aggregate rule**: any member up → the toggle stops all members; otherwise it
  starts all members.
- **Tray menu**: the menu follows the same `units` order, with a check mark
  while a unit is up; clicking one toggles it — the same single UAC prompt as
  the card. The tray icon colour still reflects processes only.
- **No autostart.** Starting a group at login would prompt for UAC at login;
  use the service's own start type for boot-time behavior.
- **Linux**: `systemctl` is used, with `pkexec` as the escalation fallback.

## Usage

### Managing processes and service groups

Everything is managed on the **Dashboard**, in one card flow:

- **Add** — the `+` menu in the AppBar offers "Add process" and "Add service
  group"; the welcome screen (nothing configured) offers both too
- **Edit** — click the pencil icon on any card or in the detail page AppBar
- **Duplicate** — open the process edit form and click "Duplicate"
- **Delete** — open the edit form and click "Delete" (requires confirmation;
  warns if the process is running)
- **Reorder** — long-press and drag a card to a new position, across kinds
- **Start/Stop** — toggle button on each card or in the detail page

### Settings

The Settings page (gear icon) contains only global options:

- **Output refresh (ms)** — batch interval for output display (100ms steps, 100–5000)
- **History limit** — max output lines per process (500-line steps, 100–100000)
- **Dashboard layout** — arrange cards as a list or a grid
- **Launch at startup** — register TrayForge for OS-level autostart

## Build & Run

### Prerequisites

- Flutter SDK ≥ 3.12.2
- Windows: Visual Studio 2022 with "Desktop development with C++"
- Linux: `gtk3`, `libappindicator` (or similar tray support)

### Run in debug mode

```bash
flutter run -d windows
```

### Build release

```bash
# Windows
flutter build windows

# Linux
flutter build linux
```

Build output lands in `build/windows/x64/runner/Release/` (Windows) or
`build/linux/x64/release/bundle/` (Linux).

## Project structure

```
lib/
├── main.dart                          # Entry point, DI, window/tray lifecycle
├── foundation/
│   ├── models.dart                    # UnitConfig, ProcessConfig, ServiceConfig, AppConfig
│   ├── logger.dart                    # File-backed logger
│   ├── output_pipeline.dart           # ANSI stripping, WebUI URL detection
│   ├── shlex.dart                     # Shell-like command splitting
│   ├── elevated_process_win32.dart    # UAC launch broker
│   ├── log_file_tailer.dart           # log_file tailing into the output pane
│   ├── service_host.dart              # Service-control seam
│   ├── service_host_win32.dart        # Windows SCM adapter (FFI)
│   ├── service_host_linux.dart        # systemd adapter (systemctl + pkexec)
│   ├── service_host_platform.dart     # Picks the host adapter for the OS
│   ├── service_operator.dart          # Direct/elevated operation policy
│   ├── service_status.dart            # ServiceState + aggregate mapping
│   ├── process_cwd.dart               # FFI binding for process-cwd lookup
│   ├── process_cwd_win32.dart         # Windows: NtQuerySystemInformation
│   └── process_cwd_linux.dart         # Linux: /proc/<pid>/cwd
├── services/
│   ├── config_store.dart              # config.json read/write with backups
│   ├── process_controller.dart        # Per-process lifecycle state machine
│   ├── process_manager.dart           # Process lifecycle (start/stop/restart)
│   ├── process_runner.dart            # IProcessRunner + real + mock impls
│   ├── service_controller.dart        # Per-group state machine + operation log
│   ├── service_elevation.dart         # --service-op helper mode
│   ├── service_manager.dart           # Group controllers + per-group streams
│   ├── single_instance.dart           # Named mutex / lock file
│   └── autostart.dart                 # OS autostart registration
├── viewmodels/
│   ├── dashboard_viewmodel.dart       # One ordered unit list: both kinds
│   ├── tray_viewmodel.dart
│   ├── process_viewmodel.dart
│   ├── service_viewmodel.dart
│   └── settings_viewmodel.dart
├── screens/
│   ├── dashboard_screen.dart
│   ├── process_detail_screen.dart
│   ├── process_edit_page.dart
│   ├── service_detail_page.dart
│   ├── service_edit_page.dart
│   └── settings_page.dart
└── widgets/
    ├── process_card.dart
    ├── service_card.dart
    ├── service_status_row.dart
    ├── follow_scroll.dart
    ├── status_dot.dart
    ├── toggle_button.dart
    ├── copy_snackbar.dart
    └── webui_copy_button.dart
```

## License

MIT
