# Per-Process Auto-Restart Configuration

## Summary

Each process in TrayForge can independently configure its maximum auto-restart attempts. Default is 0 (no auto-restart). The hardcoded global `MAX_RESTARTS = 3` is removed.

## Motivation

- Different processes have different reliability profiles. NapCat may need restart retries; a one-shot script should never auto-restart.
- Currently all processes share the same hardcoded limit of 3. Users cannot disable or tune it per process.
- Setting the default to 0 means auto-restart is opt-in, preventing unexpected restart loops for processes that shouldn't restart.

## Design

### Data Model

**`ProcessConfig` (trayforge_types.py)** — add field `max_restarts: int`.

**`ProcessStatus` (trayforge_types.py)** — `max_restarts` field already exists. Source changes from global constant to per-process config value.

### ProcessManager (`process_mgr.py`)

Remove `MAX_RESTARTS = 3`. Each site that currently reads it reads `ps.cfg.get("max_restarts", 0)` instead:

| Location | Change |
|---|---|
| `poll_crashes()` restart gate | `ps.restarts >= ps.cfg.get("max_restarts", 0)` — if max_restarts is 0, the process is never auto-restarted |
| `_stop_internal()` | `ps.restarts = ps.cfg.get("max_restarts", 0)` — suppresses restart after manual stop |
| `get_status()` | Return `ps.cfg.get("max_restarts", 0)` instead of `MAX_RESTARTS` |

When `max_restarts` is 0 and the process exits, `poll_crashes()` treats it as max restarts reached: clears `ps.proc`, emits a simpler message (e.g. "{name} exited (code={ret})" without the "max restart attempts" phrasing, since 0 means restarts were never enabled), does not restart.

`_stop_internal()` assigns `ps.restarts = ps.cfg.get("max_restarts", 0)`. Note: this may *increase* `ps.restarts` if the process crashed fewer times than the limit (e.g. 2 crashes with limit=5). This is intentional — the assignment suppresses further auto-restart after manual stop regardless of crash history.

`restart()` method: no change needed. It already resets `ps.restarts = 0` after calling `_stop_internal()`, which overrides the `_stop_internal` assignment.

Auto-restart log format string (line 172): update `{MAX_RESTARTS}` → `{ps.cfg.get("max_restarts", 0)}`.

### Config Defaults (`config.py`)

Both example processes (NapCat, AstrBot) get `"max_restarts": 0`.

### Config UI (`config_ui.py`)

Add a `ttk.Spinbox` in the existing checkboxes row (`check_frame`, row 4), packed inline after the existing checkboxes:

```
[Singleton] [Autostart] [Cleanup CWD]  Restart limit: [0]  (0=no restart)
```

Widget: `ttk.Spinbox`, `from_=0`, `to=99`, `increment=1`, `width=4`.

Changes to helper methods:

- `_build_process_row()` — add Spinbox to `check_frame`
- `_add_process()` defaults — add `"max_restarts": "0"`
- `_load_current_config()` — add `"max_restarts": str(proc.get("max_restarts", 0))`
- `_on_save()` — add `"max_restarts": int(v["max_restarts"].get())`
- `_copy_process()` — add `"max_restarts": v["max_restarts"].get()`

Validation: `_on_save()` wraps `int(v["max_restarts"].get())` in `try/except ValueError` with fallback to 0, guarding against empty-string input from direct text editing (Spinbox `from_`/`to` only clamp arrow-button actions, not typed text).

### Backward Compatibility

Existing configs without `max_restarts` default to 0 via `cfg.get("max_restarts", 0)`. No migration code required.

## Files Changed

| File | Change |
|---|---|
| `src/trayforge_types.py` | Add `max_restarts: int` to `ProcessConfig` |
| `src/process_mgr.py` | Remove `MAX_RESTARTS`, use per-process cfg value |
| `src/config.py` | Add `"max_restarts": 0` to example processes |
| `src/config_ui.py` | Add Spinbox to check_frame; wire through load/save/copy |
| `tests/test_process_mgr.py` | Update tests that reference `MAX_RESTARTS` |
| `tests/test_http_server.py` | Update `max_restarts` expected value in test fixtures |
| `tests/test_headless_controller.py` | Same |
| `tests/conftest.py` | Verified: no change (fixture configs default to max_restarts=0 via cfg.get fallback) |
| `src/http_server.py` | Verified: no change (reads max_restarts from get_status(), format string unchanged) |

## Testing

- Existing tests: update `max_restarts` assertions from 3 to 0 (new default). Affected locations:
  - `test_process_mgr.py`:296,317 — change `assert status["max_restarts"] == 3` to `== 0`
  - `test_http_server.py`:32,42,252 — change `"max_restarts": 3` to `0` in mock returns
  - `test_headless_controller.py`:25 — same
- `test_max_restarts_reached_stops_process` — set `max_restarts=3` in config (add kwarg to `_make_config()` or pass in a custom config dict), remove `from process_mgr import MAX_RESTARTS`, set `pm._procs["TestProc"].restarts = 3`, verify stop message appears
- New test: process with `max_restarts=0` exits → no auto-restart, simple exit message only
