# Output History Limit — Configurable Max Log Lines

## Summary

Replace the hardcoded `MAX_LINES = 5000` in `main_window.py` with a user-configurable global setting "Output history limit" (`output_history_limit`) accessible from the Settings dialog. Default 1000, range 100–unbounded, increment 100. GUI only (does not affect headless log files).

## Design

### Data Model

Add `output_history_limit: int` to `AppConfig` TypedDict (`trayforge_types.py`). Default 1000 in `get_default_config()`.

Config key: `"output_history_limit"`. Backward compatibility: `cfg.get("output_history_limit", 1000)` where old configs lack the field.

### Files and Changes

#### 1. `src/trayforge_types.py`
- Add `output_history_limit: int` to `AppConfig` TypedDict.

#### 2. `src/config.py`
- `get_default_config()`: add `"output_history_limit": 1000` entry.

#### 3. `src/main_window.py`
- Delete module-level `MAX_LINES = 5000`.
- `__init__`: add `self._max_lines = 1000` (matches config default).
- `_append_output_impl`: replace `MAX_LINES` with `self._max_lines`.
- Add `set_output_history_limit(self, limit: int) -> None` for runtime config reloads.
  Called by `AppController` after config is loaded/reloaded.

#### 4. `src/config_ui.py`
- Global section: add Spinbox row after poll_interval:
  - Label: "Output history limit:"
  - `ttk.Spinbox(from_=100, to=999999, increment=100, width=7)`
  - Variable: `self.output_history_limit_var = tk.StringVar(value="1000")`
- `_load_current_config`: read `output_history_limit` from config.
- `_validate()`: add clause to reject non-numeric or <100 values (Spinbox allows arbitrary text input despite `from_`/`to` constraints).
- `_on_save`: save `int(self.output_history_limit_var.get())` into config dict.

#### 5. `src/app_controller.py`
- `start()`: after config is known, call `self._window.set_output_history_limit(config["output_history_limit"])`.
- `_make_settings_callback()` / `open_settings()` closure: call `self._window.set_output_history_limit(self._config.get("output_history_limit", 1000))` after `set_processes()`. This is the primary runtime-change path (Settings → Save).
- `_reload_config()`: call `self._window.set_output_history_limit(new_config["output_history_limit"])` on reload.

### Data Flow

```
config.json  →  AppConfig["output_history_limit"]
                        ↓
AppController.start()  →  window.set_output_history_limit()
AppController._make_settings_callback()  →  window.set_output_history_limit()  (Settings → Save)
AppController._reload_config()  →  window.set_output_history_limit()  (CLI reload)
                        ↓
MainWindow._append_output_impl()  →  trims lines > self._max_lines
```

ConfigDialog reads/writes `output_history_limit` through Spinbox → `_on_save` writes to `config.json`.

### Testing Impact

All test config dicts should include `"output_history_limit": 1000` for consistent coverage. Files with config fixtures:

- `tests/conftest.py`: `pm` fixture config dict
- `tests/test_process_mgr.py`: `_make_config()` helper used by 22 test cases
- `tests/test_integration.py`: `_write_test_config()` for end-to-end tests

Test-specific changes:
- `test_main_window.py`: update `test_trims_old_lines` — monkeypatch instance `_max_lines` instead of module constant.
- `test_config.py`: `test_default_config_structure` — add assertion for `output_history_limit`.
- `test_config_ui.py`: add assertion for `output_history_limit` in `test_produces_correct_config`; add test for validation of non-numeric / <100 input.
