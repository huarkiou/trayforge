# Output History Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded `MAX_LINES = 5000` with configurable `output_history_limit` (default 1000) controllable from Settings dialog.

**Architecture:** Add `output_history_limit: int` to `AppConfig`, wire through `AppController` to `MainWindow._max_lines`, expose Spinbox in `ConfigDialog` global section.

**Tech Stack:** Python 3.11+, tkinter, pytest

## Global Constraints

- Backward compatibility: `cfg.get("output_history_limit", 1000)` for old configs lacking the field
- Range: 100+, Spinbox arrows to 999999, user can type arbitrary value
- GUI-only (headless mode writes to log files, not affected)
- Two runtime-update paths: Settings→Save (`_make_settings_callback`) and CLI reload (`_reload_config`)

---

### Task 1: Add `output_history_limit` to AppConfig TypedDict

**Files:**
- Modify: `src/trayforge_types.py`

**Interfaces:**
- Produces: `AppConfig` now requires `output_history_limit: int`

- [ ] **Step 1: Add field to AppConfig**

```python
class AppConfig(TypedDict):
    processes: list[ProcessConfig]
    output_refresh_ms: int
    poll_interval_ms: int
    autostart: bool
    output_history_limit: int
```

- [ ] **Step 2: Commit**

```bash
git add src/trayforge_types.py && git commit -m "feat: add output_history_limit to AppConfig TypedDict"
```

---

### Task 2: Add default value to config.py

**Files:**
- Modify: `src/config.py`

**Interfaces:**
- Consumes: `AppConfig.output_history_limit` (Task 1)
- Produces: `get_default_config()` returns `"output_history_limit": 1000`

- [ ] **Step 1: Add default entry**

In `get_default_config()`, after `"autostart": False,` add:

```python
        "output_history_limit": 1000,
```

- [ ] **Step 2: Commit**

```bash
git add src/config.py && git commit -m "feat: add output_history_limit default to config"
```

---

### Task 3: Replace MAX_LINES with instance variable in main_window.py

**Files:**
- Modify: `src/main_window.py`

**Interfaces:**
- Consumes: none (standalone change)
- Produces: `MainWindow.set_output_history_limit(limit: int) -> None`, `MainWindow._max_lines`

- [ ] **Step 1: Remove module-level MAX_LINES**

Delete line ~11: `MAX_LINES = 5000`

- [ ] **Step 2: Add _max_lines to __init__**

In `__init__`, after `self._logger = get_main_logger()`, add:

```python
        self._max_lines = 1000
```

- [ ] **Step 3: Update _append_output_impl to use self._max_lines**

Replace the `MAX_LINES` references in `_append_output_impl`:

```python
    def _append_output_impl(self, process_name: str, line: str) -> None:
        text = self._tabs.get(process_name)
        if text is None:
            return

        text.config(state=tk.NORMAL)
        text.insert(tk.END, line + "\n")

        line_count = int(text.index("end-1c").split(".")[0])
        if line_count > self._max_lines:
            excess = line_count - self._max_lines
            text.delete("1.0", f"{excess}.0")

        text.config(state=tk.DISABLED)
        text.see(tk.END)
```

- [ ] **Step 4: Add set_output_history_limit method**

Add after `set_processes` method:

```python
    def set_output_history_limit(self, limit: int) -> None:
        """Update the max log lines shown per-process tab."""
        self._max_lines = max(limit, 0)
```

- [ ] **Step 5: Commit**

```bash
git add src/main_window.py && git commit -m "feat: replace MAX_LINES constant with configurable _max_lines"
```

---

### Task 4: Add Spinbox to config_ui.py

**Files:**
- Modify: `src/config_ui.py`

**Interfaces:**
- Consumes: `AppConfig.output_history_limit` (Task 1); `get_default_config`, `load_config`, `save_config` from `config` (existing)
- Produces: Spinbox in global section reads/writes `output_history_limit`

- [ ] **Step 1: Add Spinbox widget in Global section**

In `_build_ui()`, after the poll_interval Spinbox block (after `ttk.Spinbox(...).pack(...)` for poll_interval), add:

```python
        history_frame = ttk.Frame(global_frame)
        history_frame.pack(fill=tk.X, pady=2)
        ttk.Label(history_frame, text="Output history limit:").pack(side=tk.LEFT)
        self.output_history_limit_var = tk.StringVar(value="1000")
        ttk.Spinbox(
            history_frame,
            textvariable=self.output_history_limit_var,
            from_=100,
            to=999999,
            increment=100,
            width=7,
        ).pack(side=tk.LEFT, padx=(5, 0))
```

- [ ] **Step 2: Load value in _load_current_config**

In `_load_current_config()`, after `self.poll_interval_var.set(...)`, add:

```python
        self.output_history_limit_var.set(
            str(config.get("output_history_limit", 1000))
        )
```

- [ ] **Step 3: Add validation in _validate()**

In `_validate()`, after the `max_restarts` validation block, add:

```python
        try:
            limit = int(self.output_history_limit_var.get())
            if limit < 100:
                return "Output history limit must be at least 100."
        except (ValueError, TypeError):
            return "Output history limit must be a number."
```

- [ ] **Step 4: Save value in _on_save**

In `_on_save()`, add `"output_history_limit"` to the config dict (alongside `poll_interval_ms`):

```python
        config: AppConfig = {
            "processes": processes,
            "output_refresh_ms": int(self.output_refresh_var.get()),
            "poll_interval_ms": int(self.poll_interval_var.get()),
            "output_history_limit": int(self.output_history_limit_var.get()),
            "autostart": self.autostart_var.get(),
        }
```

- [ ] **Step 5: Commit**

```bash
git add src/config_ui.py && git commit -m "feat: add output history limit Spinbox to settings dialog"
```

---

### Task 5: Wire up in app_controller.py

**Files:**
- Modify: `src/app_controller.py`

**Interfaces:**
- Consumes: `MainWindow.set_output_history_limit` (Task 3), `AppConfig.output_history_limit` (Task 1)
- Produces: limit propagates to window on start, settings save, and config reload

- [ ] **Step 1: Call set_output_history_limit in _make_settings_callback closure**

In the `open_settings()` closure inside `_make_settings_callback()`, after `self._window.set_processes(self._pm.process_names())`, add:

```python
                self._window.set_output_history_limit(
                    self._config.get("output_history_limit", 1000)
                )
```

- [ ] **Step 2: Call set_output_history_limit in _reload_config**

In `_reload_config()`, after `self._window.set_processes(self._pm.process_names())`, add:

```python
            self._window.set_output_history_limit(
                config.get("output_history_limit", 1000)
            )
```

- [ ] **Step 3: Call set_output_history_limit in start**

In `start()`, after `window.set_processes(pm.process_names())` in `main.pyw` does the initial population, the `AppController.start()` method should propagate. Add after the autostart loop, before the HTTP server block:

```python
        self._window.set_output_history_limit(
            self._config.get("output_history_limit", 1000)
        )
```

Place right before `# Start HTTP server for CLI control` comment.

- [ ] **Step 4: Commit**

```bash
git add src/app_controller.py && git commit -m "feat: wire output_history_limit through AppController"
```

---

### Task 6: Update test fixtures and tests

**Files:**
- Modify: `tests/conftest.py`
- Modify: `tests/test_process_mgr.py`
- Modify: `tests/test_integration.py`
- Modify: `tests/test_config.py`
- Modify: `tests/test_main_window.py`
- Modify: `tests/test_config_ui.py`

**Interfaces:**
- Consumes: all changes from Tasks 1–5

- [ ] **Step 1: Update conftest.py pm fixture**

Add `"output_history_limit": 1000` to the config dict in `pm` fixture, after `"autostart": False,`:

```python
    return ProcessManager({
        "processes": [...],
        "output_refresh_ms": 500,
        "poll_interval_ms": 2000,
        "output_history_limit": 1000,
        "autostart": False,
    })
```

- [ ] **Step 2: Update test_process_mgr.py _make_config()**

Add `"output_history_limit": 1000` to the returned dict in `_make_config()`, after `"autostart": False,`:

```python
    return {
        "processes": processes,
        "output_refresh_ms": 500,
        "poll_interval_ms": 2000,
        "output_history_limit": 1000,
        "autostart": False,
    }
```

- [ ] **Step 3: Update test_integration.py _write_test_config()**

Add `"output_history_limit": 1000` to the test_config dict, after `"autostart": False,`:

```python
        "output_history_limit": 1000,
```

- [ ] **Step 4: Update test_config.py default config assertion**

In `test_default_config_structure`, add assertion:

```python
    assert cfg["output_history_limit"] == 1000
```

- [ ] **Step 5: Fix test_main_window.py test_trims_old_lines**

Replace the monkeypatch on `mw.MAX_LINES` with monkeypatching the instance attribute:

```python
    def test_trims_old_lines(self, window, monkeypatch):
        window._max_lines = 4
        window.set_processes(["A"])
        text = window._tabs["A"]
        for i in range(6):
            window._append_output_impl("A", f"line {i}")
        # After 6 inserts with _max_lines=4, oldest 2 lines trimmed
        content = text.get("1.0", "end-1c").rstrip("\n")
        lines = content.split("\n")
        assert lines[0] == "line 2"
        assert lines[-1] == "line 5"
```

Remove the `import main_window as mw` line in this test (the monkeypatch block).

- [ ] **Step 6: Update test_config_ui.py test_produces_correct_config**

In `test_produces_correct_config`, after `assert result["output_refresh_ms"] == 300`, add:

```python
                assert result.get("output_history_limit", 1000) == 1000
```

- [ ] **Step 7: Add validation test in test_config_ui.py**

Add new test class after `TestValidate`:

```python
class TestOutputHistoryLimitValidation:
    def test_rejects_non_numeric(self, dlg):
        dlg.output_history_limit_var = tk.StringVar(value="abc")
        err = dlg._validate()
        assert err is not None
        assert "Output history limit must be a number" in err

    def test_rejects_below_100(self, dlg):
        dlg.output_history_limit_var = tk.StringVar(value="50")
        err = dlg._validate()
        assert err is not None
        assert "at least 100" in err
```

- [ ] **Step 8: Commit**

```bash
git add tests/ && git commit -m "test: update test fixtures and assertions for output_history_limit"
```

---

### Task 7: Run full test suite and verify

- [ ] **Step 1: Run ruff format**

```bash
cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/ tests/
```
Expected: zero changes (already formatted)

- [ ] **Step 2: Run ruff check**

```bash
cd /mnt/d/Projects/Program/TrayForge && uv run ruff check src/ tests/
```
Expected: All checks passed, zero errors

- [ ] **Step 3: Run ty check**

```bash
cd /mnt/d/Projects/Program/TrayForge && uv run ty check src/
```
Expected: zero type errors

- [ ] **Step 4: Run unit tests**

```bash
cd /mnt/d/Projects/Program/TrayForge && uv run pytest tests/ -v --ignore=tests/test_integration.py
```
Expected: ~136 unit tests pass (integration excluded since it needs desktop session; exact count may vary with new tests added)

- [ ] **Step 5: Commit if any cleanups needed**

```bash
git add -A && git commit -m "chore: final formatting and lint fixes"
```
