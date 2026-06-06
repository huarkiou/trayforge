# Per-Process Auto-Restart Configuration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-process `max_restarts` config field (default 0), replacing the hardcoded `MAX_RESTARTS = 3`. Wire through data model, ProcessManager, and config UI.

**Architecture:** One new int field in `ProcessConfig` TypedDict. ProcessManager reads it from `ps.cfg.get("max_restarts", 0)` at each site that previously used `MAX_RESTARTS`. Config UI adds a Spinbox in the existing checkboxes row.

**Tech Stack:** Python 3.12, tkinter, pytest, unittest.mock

---

### Task 1: Data model and defaults

**Files:**
- Modify: `src/trayforge_types.py`
- Modify: `src/config.py`

- [ ] **Step 1: Add `max_restarts` to `ProcessConfig` TypedDict**

```python
# src/trayforge_types.py — in ProcessConfig class, after `cleanup_cwd` line:
class ProcessConfig(TypedDict):
    name: str
    cwd: str
    cmd: str
    encoding: str
    singleton: bool
    autostart: bool
    cleanup_cwd: bool
    webui_pattern: str | None
    delete_before_start: list[str]
    max_restarts: int
```

- [ ] **Step 2: Add `max_restarts: 0` to example processes in `get_default_config()`**

```python
# src/config.py — add to both example process dicts:
    "max_restarts": 0,
```

(Add after `"delete_before_start": [],` in NapCat, and after `"delete_before_start": ["astrbot.lock"],` in AstrBot.)

- [ ] **Step 3: Verify module imports cleanly**

Run: `uv run python -c "from trayforge_types import ProcessConfig; print('OK')"`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add src/trayforge_types.py src/config.py
git commit -m "feat: add max_restarts field to ProcessConfig and defaults"
```

---

### Task 2: ProcessManager — write tests

**Files:**
- Modify: `tests/test_process_mgr.py`

- [ ] **Step 1: Update `test_get_status` assertions from 3 → 0 (two locations: ~line 296 and ~line 317)**

```python
# In test_get_status_returns_dict_for_known_process:
        assert status["max_restarts"] == 0

# In test_get_status_reflects_running_state:
        assert status["max_restarts"] == 0
```

- [ ] **Step 2: Add `max_restarts` to `_make_config` default dict and add non-zero kwarg support**

Update `_make_config` to include `max_restarts` in its default process dict, and accept a `max_restarts` kwarg for the test that needs a non-zero value:

```python
def _make_config(processes=None, max_restarts=0):
    if processes is None:
        processes = [
            {
                "name": "TestProc",
                "cwd": "",
                "cmd": "echo hello",
                "encoding": "utf-8",
                "singleton": False,
                "autostart": False,
                "webui_pattern": None,
                "delete_before_start": [],
                "max_restarts": max_restarts,
            }
        ]
    return {
        "processes": processes,
        "output_refresh_ms": 500,
        "poll_interval_ms": 2000,
        "autostart": False,
    }
```

- [ ] **Step 3: Rewrite `test_max_restarts_reached_stops_process` to use per-process config**

```python
@patch("subprocess.Popen")
@patch("threading.Thread")
def test_max_restarts_reached_stops_process(self, mock_thread, mock_popen):
    mock_proc = MagicMock()
    mock_proc.pid = 12345
    mock_proc.poll.return_value = 1
    mock_popen.return_value = mock_proc

    cfg = _make_config(max_restarts=3)
    pm = ProcessManager(cfg)
    pm._start("TestProc")

    pm._procs["TestProc"].restarts = 3
    pm.poll_crashes()

    assert pm._procs["TestProc"].proc is None
    lines = pm.drain("TestProc")
    assert any("max restart attempts" in line.lower() for line in lines)
```

Remove `from process_mgr import MAX_RESTARTS` import inside this test method — it no longer exists.

- [ ] **Step 4: Add new test: `max_restarts=0` should never auto-restart**

```python
@patch("subprocess.Popen")
@patch("threading.Thread")
def test_max_restarts_zero_stops_no_restart(self, mock_thread, mock_popen):
    mock_proc = MagicMock()
    mock_proc.pid = 12345
    mock_proc.poll.return_value = 1
    mock_popen.return_value = mock_proc

    cfg = _make_config(max_restarts=0)
    pm = ProcessManager(cfg)
    pm._start("TestProc")

    pm.poll_crashes()

    # Process should be cleared (treated as max reached)
    assert pm._procs["TestProc"].proc is None
    lines = pm.drain("TestProc")
    # Should NOT contain "auto-restarting" since max_restarts=0
    assert not any("auto-restarting" in line.lower() for line in lines)
    # Should contain exit message
    assert any("exited" in line.lower() for line in lines)
```

- [ ] **Step 5: Run tests — expect failures**

Run: `uv run pytest tests/test_process_mgr.py -v`
Expected: test_get_status assertions fail (still 3), test_max_restarts_reached fails (MAX_RESTARTS import)

- [ ] **Step 6: Commit**

```bash
git add tests/test_process_mgr.py
git commit -m "test: update ProcessManager tests for per-process max_restarts"
```

---

### Task 3: ProcessManager — implementation

**Files:**
- Modify: `src/process_mgr.py`

- [ ] **Step 1: Remove `MAX_RESTARTS = 3` constant**

Delete line 26:
```python
MAX_RESTARTS = 3
```

(Also delete the blank line after it, line 27.)

- [ ] **Step 2: Update `poll_crashes()` — restart gate and messages**

In `poll_crashes()`, change the `MAX_RESTARTS` references. Compute `max_r` once at the top of the per-process loop body. The method has three sites:

Site 1 (~line 144) — restart limit gate. When `max_r == 0`, emit a simpler exit message (no "max restart attempts" phrasing):
```python
# Before:
                if ps.restarts >= MAX_RESTARTS:
                    ps.proc = None
                    ps.webui_url = None
                    self._system_msg(
                        name,
                        f"{name} max restart attempts ({MAX_RESTARTS}) reached, stopped",
                    )
                    self._emit_status()
                    continue
# After:
                max_r = ps.cfg.get("max_restarts", 0)
                if ps.restarts >= max_r:
                    ps.proc = None
                    ps.webui_url = None
                    if max_r > 0:
                        self._system_msg(
                            name,
                            f"{name} max restart attempts ({max_r}) reached, stopped",
                        )
                    else:
                        self._system_msg(
                            name,
                            f"{name} exited (code={ret})",
                        )
                    self._emit_status()
                    continue
```

Site 2 (~line 172) — auto-restart log message (only reached when `max_r > 0` since `ps.restarts >= max_r` with `max_r=0` always hits the gate):
```python
# Before:
                self._system_msg(
                    name,
                    f"{name} exited (code={ret}), auto-restarting ({ps.restarts}/{MAX_RESTARTS})...",
                )
# After:
                self._system_msg(
                    name,
                    f"{name} exited (code={ret}), auto-restarting ({ps.restarts}/{max_r})...",
                )
```

- [ ] **Step 3: Update `_stop_internal()` — suppress restart after manual stop**

```python
# Before:
        ps.restarts = MAX_RESTARTS
# After:
        ps.restarts = ps.cfg.get("max_restarts", 0)
```

- [ ] **Step 4: Update `get_status()` — return per-process max_restarts**

```python
# Before (~line 115):
            "max_restarts": MAX_RESTARTS,
# After:
            "max_restarts": ps.cfg.get("max_restarts", 0),
```

- [ ] **Step 5: Run tests — expect pass**

Run: `uv run pytest tests/test_process_mgr.py -v`
Expected: All 23 tests PASS (including the new one and the updated ones)

- [ ] **Step 6: Commit**

```bash
git add src/process_mgr.py
git commit -m "feat: per-process max_restarts in ProcessManager"
```

---

### Task 4: Config UI

**Files:**
- Modify: `src/config_ui.py`

- [ ] **Step 1: Add Spinbox to `check_frame` in `_build_process_row()`**

After the `Cleanup CWD` Checkbutton `pack()` call, add:

```python
        # Restart limit Spinbox (inline in check_frame)
        ttk.Label(check_frame, text="Restart limit:").pack(
            side=tk.LEFT, padx=(15, 2)
        )
        v["max_restarts"] = tk.StringVar(value=str(defaults.get("max_restarts", "0")))
        ttk.Spinbox(
            check_frame,
            textvariable=v["max_restarts"],
            from_=0,
            to=99,
            increment=1,
            width=4,
        ).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Label(check_frame, text="(0=no restart)", foreground="gray").pack(
            side=tk.LEFT
        )
```

- [ ] **Step 2: Add `max_restarts` default to `_add_process()`**

In the defaults dict, add after `"delete_before_start": ""`:
```python
                "max_restarts": "0",
```

- [ ] **Step 3: Add `max_restarts` load to `_load_current_config()`**

In the `_add_process` call's defaults dict, add after `"delete_before_start": ...`:
```python
                    "max_restarts": str(proc.get("max_restarts", 0)),
```

- [ ] **Step 4: Add `max_restarts` save to `_on_save()` with inline validation**

In the processes builder loop, add after `"delete_before_start": ...`:
```python
                    "max_restarts": int(v["max_restarts"].get() or 0),
```

Using `or 0` guards against empty-string input from direct text editing (Spinbox `from_`/`to` only clamp arrow-button actions, not typed text). If the value is empty string, `int("" or 0)` → `int(0)` → `0`. No module-level helper needed.

- [ ] **Step 5: Add `max_restarts` copy to `_copy_process()`**

In the defaults dict, add after `"delete_before_start": ...`:
```python
            "max_restarts": v["max_restarts"].get(),
```

- [ ] **Step 6: Verify UI loads without errors**

Run: `uv run python -c "import tkinter as tk; from config_ui import ConfigDialog; print('import OK')"`
Expected: `import OK`

(Full UI test requires desktop session — done manually or via integration test.)

- [ ] **Step 7: Commit**

```bash
git add src/config_ui.py
git commit -m "feat: add max_restarts Spinbox to config UI"
```

---

### Task 5: Update test fixtures and final verification

**Files:**
- Modify: `tests/test_http_server.py`
- Modify: `tests/test_headless_controller.py`

- [ ] **Step 1: Update `test_http_server.py` mock values and assertions**

Mock values (three locations ~lines 32, 42, 252) — change `"max_restarts": 3` to `"max_restarts": 0`:

```python
# Line 32:
            "max_restarts": 0,
# Line 42:
            "max_restarts": 0,
# Line 252:
                "max_restarts": 0,
```

Status endpoint assertion (~line 120) — change `"Restarts: 1/3"` to `"Restarts: 1/0"`:

```python
        assert "Restarts: 1/0" in body
```

- [ ] **Step 2: Update `test_headless_controller.py` mock value**

Line 25 — change `"max_restarts": 3` to `"max_restarts": 0`:

```python
        "max_restarts": 0,
```

- [ ] **Step 3: Run full test suite**

Run: `uv run pytest tests/ -v`
Expected: 135 tests PASS

- [ ] **Step 4: Run ruff**

Run: `uv run ruff format src/ && uv run ruff check src/`
Expected: clean

- [ ] **Step 5: Commit**

```bash
git add tests/test_http_server.py tests/test_headless_controller.py
git commit -m "test: update fixture max_restarts to new default 0"
```
