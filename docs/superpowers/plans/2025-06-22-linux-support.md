# Linux Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TrayForge fully functional on Linux with ~133 lines of changes across 9 files, zero new files.

**Architecture:** Extend existing `if sys.platform == "win32"` branch pattern with `else` branches for Linux. No abstraction layer, no new modules. Each file handles its own platform differences internally.

**Tech Stack:** Python 3.11+, psutil, pystray, tkinter, fcntl, signal

## Global Constraints

- Zero new files, no architecture changes
- All changes follow existing `if sys.platform == "win32"` branch pattern
- `ruff format src/ tests/` must pass (zero changes)
- `ruff check src/ tests/` must pass (zero errors)
- `mypy src/` must pass (zero errors)
- Python 3.11+ required (`start_new_session` available since 3.2)

---

### Task 1: XDG Data Directories (`config.py` + `logger.py`)

**Files:**
- Modify: `src/config.py:13-21`
- Modify: `src/logger.py:9-13`

**Interfaces:**
- Produces: `get_data_dir()` returns `$XDG_DATA_HOME/TrayForge` on Linux (unchanged API)
- Produces: `_get_log_dir()` returns `$XDG_STATE_HOME/TrayForge/logs` on Linux (unchanged API)

- [ ] **Step 1: Modify `config.py` `get_data_dir()` — add Linux XDG branch**

In `src/config.py`, lines 13-21, replace the current function body:

```python
# Current (lines 13-21):
def get_data_dir() -> str:
    """Get or create the data directory. Respects TRAYFORGE_DATA_DIR env var."""
    custom = os.environ.get("TRAYFORGE_DATA_DIR")
    if custom:
        os.makedirs(custom, exist_ok=True)
        return custom
    local_appdata = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
    data_dir = os.path.join(local_appdata, "TrayForge")
    os.makedirs(data_dir, exist_ok=True)
    return data_dir
```

Replace with:

```python
def get_data_dir() -> str:
    """Get or create the data directory. Respects TRAYFORGE_DATA_DIR env var."""
    custom = os.environ.get("TRAYFORGE_DATA_DIR")
    if custom:
        os.makedirs(custom, exist_ok=True)
        return custom
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
    else:
        base = os.environ.get(
            "XDG_DATA_HOME",
            os.path.join(os.path.expanduser("~"), ".local", "share"),
        )
    data_dir = os.path.join(base, "TrayForge")
    os.makedirs(data_dir, exist_ok=True)
    return data_dir
```

Also add `import sys` at the top of `config.py` (line 3, after `import os`):

```python
import sys
```

- [ ] **Step 2: Modify `logger.py` `_get_log_dir()` — add Linux XDG branch**

In `src/logger.py`, lines 9-13, replace:

```python
# Current (lines 9-13):
def _get_log_dir() -> str:
    """Get or create the log directory under LOCALAPPDATA."""
    local_appdata = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
    log_dir = os.path.join(local_appdata, "TrayForge", "logs")
    os.makedirs(log_dir, exist_ok=True)
    return log_dir
```

Replace with:

```python
def _get_log_dir() -> str:
    """Get or create the log directory."""
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
    else:
        base = os.environ.get(
            "XDG_STATE_HOME",
            os.path.join(os.path.expanduser("~"), ".local", "state"),
        )
    log_dir = os.path.join(base, "TrayForge", "logs")
    os.makedirs(log_dir, exist_ok=True)
    return log_dir
```

Also add `import sys` at the top of `logger.py` (line 3, after `import os`):

```python
import sys
```

- [ ] **Step 3: Verify — ruff + mypy**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/config.py src/logger.py && uv run ruff check src/config.py src/logger.py`
Expected: zero changes, zero errors

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run mypy src/config.py src/logger.py`
Expected: Success: no issues found

- [ ] **Step 4: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add src/config.py src/logger.py
git commit -m "feat: XDG data directories for Linux (config.py, logger.py)"
```

---

### Task 2: Single Instance Protection (`single_instance.py`)

**Files:**
- Modify: `src/single_instance.py` (entire file, ~12 lines → ~45 lines)

**Interfaces:**
- Consumes: `config.get_data_dir()` (lazy import, no circular dep)
- Produces: `ensure_single_instance() -> bool` (unchanged API)

- [ ] **Step 1: Rewrite `single_instance.py`**

Replace entire content of `src/single_instance.py`:

```python
"""Single-instance enforcement — named mutex (Windows) or PID file + fcntl (Linux)."""

import os
import sys

if sys.platform == "win32":
    import ctypes

    MUTEX_NAME = "Global\\TrayForge_SingleInstance"
else:
    import fcntl


def ensure_single_instance() -> bool:
    """Try to acquire a system-wide lock. Returns True if we're the only instance."""
    if sys.platform == "win32":
        return _ensure_windows()
    return _ensure_linux()


def _ensure_windows() -> bool:
    kernel32 = ctypes.windll.kernel32
    kernel32.CreateMutexW(None, True, MUTEX_NAME)
    return kernel32.GetLastError() != 183  # ERROR_ALREADY_EXISTS


def _ensure_linux() -> bool:
    """Acquire an exclusive fcntl lock on a PID file in the data directory."""
    from config import get_data_dir

    lock_path = os.path.join(get_data_dir(), "instance.lock")
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_TRUNC, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.write(fd, str(os.getpid()).encode())
        _ensure_linux._lock_fd = fd  # type: ignore[attr-defined]
        return True
    except (IOError, OSError):
        try:
            os.close(fd)
        except Exception:
            pass
        return False
```

- [ ] **Step 2: Verify — ruff + mypy**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/single_instance.py && uv run ruff check src/single_instance.py`
Expected: zero changes, zero errors

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run mypy src/single_instance.py`
Expected: Success: no issues found

- [ ] **Step 3: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add src/single_instance.py
git commit -m "feat: fcntl PID file lock for Linux single-instance protection"
```

---

### Task 3: Autostart (`startup.py`)

**Files:**
- Modify: `src/startup.py` (entire file, ~63 lines → ~110 lines)

**Interfaces:**
- Produces: `is_autostart_enabled() -> bool` (unchanged API)
- Produces: `enable_autostart() -> bool` (unchanged API)
- Produces: `disable_autostart() -> bool` (unchanged API)
- Produces: `_get_exe_path() -> str` (unchanged API, cross-platform)

- [ ] **Step 1: Rewrite `startup.py`**

Replace entire content of `src/startup.py`:

```python
"""Autostart management — Windows registry or XDG autostart .desktop file."""

import os
import sys

if sys.platform == "win32":
    import winreg

    REG_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
    REG_VALUE_NAME = "TrayForge"

from logger import get_main_logger


def _get_exe_path() -> str:
    """Get the path to use for autostart entry."""
    if getattr(sys, "frozen", False):
        return sys.executable
    script_dir = os.path.dirname(os.path.abspath(__file__))
    main_script = os.path.join(script_dir, "main.pyw")
    return f'"{sys.executable}" "{main_script}"'


# --- Windows implementation ---

if sys.platform == "win32":

    def _is_enabled() -> bool:
        logger = get_main_logger()
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY, 0, winreg.KEY_READ) as key:
                winreg.QueryValueEx(key, REG_VALUE_NAME)
                return True
        except FileNotFoundError:
            return False
        except OSError as e:
            logger.error("Failed to read autostart registry: %s", e)
            return False

    def _enable() -> bool:
        logger = get_main_logger()
        exe_path = _get_exe_path()
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY, 0, winreg.KEY_SET_VALUE) as key:
                winreg.SetValueEx(key, REG_VALUE_NAME, 0, winreg.REG_SZ, exe_path)
            logger.info("Autostart enabled: %s", exe_path)
            return True
        except OSError as e:
            logger.error("Failed to enable autostart: %s", e)
            return False

    def _disable() -> bool:
        logger = get_main_logger()
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY, 0, winreg.KEY_SET_VALUE) as key:
                winreg.DeleteValue(key, REG_VALUE_NAME)
            logger.info("Autostart disabled")
            return True
        except FileNotFoundError:
            return True
        except OSError as e:
            logger.error("Failed to disable autostart: %s", e)
            return False

else:
    # --- Linux implementation ---

    def _get_desktop_path() -> str:
        config_home = os.environ.get(
            "XDG_CONFIG_HOME",
            os.path.join(os.path.expanduser("~"), ".config"),
        )
        autostart_dir = os.path.join(config_home, "autostart")
        return os.path.join(autostart_dir, "TrayForge.desktop")

    def _is_enabled() -> bool:
        return os.path.exists(_get_desktop_path())

    def _enable() -> bool:
        logger = get_main_logger()
        desktop_path = _get_desktop_path()
        exe_path = _get_exe_path()
        content = (
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=TrayForge\n"
            f"Exec={exe_path}\n"
            "Terminal=false\n"
            "StartupNotify=false\n"
            "Hidden=false\n"
        )
        try:
            os.makedirs(os.path.dirname(desktop_path), exist_ok=True)
            tmp_path = desktop_path + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(content)
            os.rename(tmp_path, desktop_path)
            logger.info("Autostart enabled: %s", desktop_path)
            return True
        except OSError as e:
            logger.error("Failed to enable autostart: %s", e)
            return False

    def _disable() -> bool:
        logger = get_main_logger()
        desktop_path = _get_desktop_path()
        try:
            os.remove(desktop_path)
            logger.info("Autostart disabled")
            return True
        except FileNotFoundError:
            return True
        except OSError as e:
            logger.error("Failed to disable autostart: %s", e)
            return False


# Public API
is_autostart_enabled = _is_enabled
enable_autostart = _enable
disable_autostart = _disable
```

- [ ] **Step 2: Verify — ruff + mypy**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/startup.py && uv run ruff check src/startup.py`
Expected: zero changes, zero errors

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run mypy src/startup.py`
Expected: Success: no issues found

- [ ] **Step 3: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add src/startup.py
git commit -m "feat: XDG autostart .desktop file for Linux (startup.py)"
```

---

### Task 4: Process Manager (`process_mgr.py`)

**Files:**
- Modify: `src/process_mgr.py:10` (add `import signal`)
- Modify: `src/process_mgr.py:234-249` (`_kill_cwd_processes` — add Linux branch)
- Modify: `src/process_mgr.py:278-279` (`_start` — un-gate cleanup_cwd)
- Modify: `src/process_mgr.py:297-299` (`_start` — un-gate delete_before_start PermissionError)
- Modify: `src/process_mgr.py:346-347` (`_start` — add start_new_session)
- Modify: `src/process_mgr.py:381-395` (`_stop_internal` — rewrite Linux branch)

**Interfaces:**
- Produces: ProcessManager API unchanged (start, stop, restart, etc.)

- [ ] **Step 1: Add `import signal` at top of file**

In `src/process_mgr.py`, after line 10 (`import time`), add:

```python
import signal
```

- [ ] **Step 2: Add Linux branch to `_kill_cwd_processes`**

In `src/process_mgr.py`, lines 234-249, replace the inner kill block:

```python
# Current (lines 234-249):
                    if sys.platform == "win32":
                        if not (
                            p_cwd
                            and os.path.normcase(os.path.normpath(p_cwd))
                            == os.path.normcase(norm_cwd)
                        ):
                            continue
                    elif not (p_cwd and os.path.normpath(p_cwd) == norm_cwd):
                        continue
                    subprocess.run(
                        ["taskkill", "/f", "/t", "/pid", str(proc.info["pid"])],
                        capture_output=True,
                        timeout=5,
                        creationflags=subprocess.CREATE_NO_WINDOW,
                    )
```

Replace with:

```python
                    if sys.platform == "win32":
                        if not (
                            p_cwd
                            and os.path.normcase(os.path.normpath(p_cwd))
                            == os.path.normcase(norm_cwd)
                        ):
                            continue
                        subprocess.run(
                            ["taskkill", "/f", "/t", "/pid", str(proc.info["pid"])],
                            capture_output=True,
                            timeout=5,
                            creationflags=subprocess.CREATE_NO_WINDOW,
                        )
                    else:
                        if not (p_cwd and os.path.normpath(p_cwd) == norm_cwd):
                            continue
                        os.kill(proc.info["pid"], signal.SIGKILL)
```

- [ ] **Step 3: Un-gate `cleanup_cwd` in `_start`**

In `src/process_mgr.py`, lines 278-280, replace:

```python
        cleanup = cfg.get("cleanup_cwd", False)
        if cleanup and sys.platform == "win32":
            self._kill_cwd_processes(cwd)
```

With:

```python
        cleanup = cfg.get("cleanup_cwd", False)
        if cleanup:
            self._kill_cwd_processes(cwd)
```

- [ ] **Step 4: Un-gate `delete_before_start` PermissionError fallback**

In `src/process_mgr.py`, lines 297-299, replace:

```python
                except PermissionError:
                    if sys.platform == "win32":
                        self._kill_cwd_processes(cwd)
                        time.sleep(0.3)
```

With:

```python
                except PermissionError:
                    self._kill_cwd_processes(cwd)
                    time.sleep(0.3)
```

- [ ] **Step 5: Add `start_new_session=True` to Popen kwargs**

In `src/process_mgr.py`, after line 347 (`kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW`), add:

```python
            if sys.platform != "win32":
                kwargs["start_new_session"] = True
```

- [ ] **Step 6: Rewrite Linux branch in `_stop_internal`**

In `src/process_mgr.py`, replace lines 381-395 (the entire `_stop_internal` platform branch):

```python
# Current (lines 381-395):
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/f", "/t", "/pid", str(pid)],
                capture_output=True,
                timeout=3,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        else:
            try:
                ps.proc.terminate()
                ps.proc.wait(timeout=2)
            except Exception:
                try:
                    ps.proc.kill()
                except Exception:
                    pass
```

Replace with:

```python
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/f", "/t", "/pid", str(pid)],
                capture_output=True,
                timeout=3,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        else:
            try:
                if os.getpgid(pid) == pid:
                    os.killpg(pid, signal.SIGTERM)
                    try:
                        ps.proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(pid, signal.SIGKILL)
                        ps.proc.wait(timeout=2)
                else:
                    ps.proc.terminate()
                    try:
                        ps.proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        ps.proc.kill()
                        ps.proc.wait(timeout=2)
            except ProcessLookupError:
                pass
```

- [ ] **Step 7: Verify — ruff + mypy**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/process_mgr.py && uv run ruff check src/process_mgr.py`
Expected: zero changes, zero errors

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run mypy src/process_mgr.py`
Expected: Success: no issues found

- [ ] **Step 8: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add src/process_mgr.py
git commit -m "feat: Linux process tree kill via os.killpg + start_new_session"
```

---

### Task 5: Settings UI Label (`config_ui.py`)

**Files:**
- Modify: `src/config_ui.py:84`

- [ ] **Step 1: Change autostart checkbox label**

In `src/config_ui.py`, line 84, replace:

```python
            text="Start TrayForge with Windows (autostart)",
```

With:

```python
            text="Start TrayForge on login",
```

- [ ] **Step 2: Verify — ruff**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/config_ui.py && uv run ruff check src/config_ui.py`
Expected: zero changes, zero errors

- [ ] **Step 3: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add src/config_ui.py
git commit -m "feat: platform-neutral autostart label in settings"
```

---

### Task 6: Test Fixture Fields (`conftest.py` + `test_process_mgr.py`)

**Files:**
- Modify: `tests/conftest.py:17-38` (add `max_restarts` to two process entries)
- Modify: `tests/test_process_mgr.py:7-20` (add `cleanup_cwd` to `_make_config` default)
- Modify: `tests/test_process_mgr.py` — add `"cleanup_cwd": False` to all inline process dicts

**Interfaces:**
- Produces: `pm` fixture now has TypedDict-compliant `ProcessConfig` entries

- [ ] **Step 1: Add `max_restarts` to conftest.py fixture**

In `tests/conftest.py`, lines 17-38, add `"max_restarts": 0` to both process entries:

```python
# NapCat entry (after line 27 "delete_before_start": [],):
                "max_restarts": 0,

# AstrBot entry (after line 38 "delete_before_start": [],):
                "max_restarts": 0,
```

- [ ] **Step 2: Add `cleanup_cwd` to `_make_config` default**

In `tests/test_process_mgr.py`, line 14 (after `"singleton": False,`), add:

```python
                "cleanup_cwd": False,
```

- [ ] **Step 3: Add `cleanup_cwd` to all inline process dicts in tests**

In `tests/test_process_mgr.py`, add `"cleanup_cwd": False,` after `"singleton": False,` (or equivalent position) in each of these inline process dicts:

- Line 43 (`TestPreservesExistingStateOnReconfig` — `"TestProc"` entry)
- Line 65 (`TestRemovesDeletedProcesses` — `"OtherProc"` entry)
- Line 98 (`TestProcessState.test_has_webui_true` — `"WebProc"` entry)
- Line 140 (`TestStartStop.test_start_empty_command` — `"BadProc"` entry)
- Line 162 (`TestStartStop.test_start_missing_cwd` — `"BadProc"` entry)
- Line 199 (`TestStartStop.test_start_all_and_stop_all` — `"Proc1"` entry)
- Line 209 (`TestStartStop.test_start_all_and_stop_all` — `"Proc2"` entry)

Each addition is one line:
```python
                "cleanup_cwd": False,
```

- [ ] **Step 4: Verify — ruff + mypy**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format tests/conftest.py tests/test_process_mgr.py && uv run ruff check tests/conftest.py tests/test_process_mgr.py`
Expected: zero changes, zero errors

- [ ] **Step 5: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add tests/conftest.py tests/test_process_mgr.py
git commit -m "test: add missing ProcessConfig fields (cleanup_cwd, max_restarts)"
```

---

### Task 7: Skip Windows Startup Tests (`test_startup.py`)

**Files:**
- Modify: `tests/test_startup.py:18,32,47,63` (add `@pytest.mark.skipif` to each test class)

- [ ] **Step 1: Add skipif decorators**

In `tests/test_startup.py`, add the following decorator to each of these 4 test classes:

Class `TestGetExePath` (line 7):
```python
@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")
class TestGetExePath:
```

Class `TestIsAutostartEnabled` (line 25):
```python
@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")
class TestIsAutostartEnabled:
```

Class `TestEnableAutostart` (line 42):
```python
@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")
class TestEnableAutostart:
```

Class `TestDisableAutostart` (line 62):
```python
@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")
class TestDisableAutostart:
```

Also add `import sys` if not already present at the top of the file (it already has `import sys` on line 3 — verify).

- [ ] **Step 2: Verify — tests run on Linux**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run pytest tests/test_startup.py -v`
Expected: 4 skipped, 0 failed (or all pass if on Windows)

- [ ] **Step 3: Commit**

```bash
cd /mnt/d/Projects/Program/TrayForge
git add tests/test_startup.py
git commit -m "test: skip Windows registry tests on Linux"
```

---

### Task 8: Final Verification

- [ ] **Step 1: ruff format all**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff format src/ tests/`
Expected: "1 file reformatted" at most (cosmetic), no errors

- [ ] **Step 2: ruff check all**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run ruff check src/ tests/`
Expected: "All checks passed!"

- [ ] **Step 3: mypy all src**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run mypy src/`
Expected: "Success: no issues found in N source files"

- [ ] **Step 4: Run test suite**

Run: `cd /mnt/d/Projects/Program/TrayForge && uv run pytest tests/ -v 2>&1 | tail -20`
Expected: All tests pass (4 startup tests skipped on Linux)

- [ ] **Step 5: Commit (if ruff format changed anything)**

```bash
cd /mnt/d/Projects/Program/TrayForge
# Only if ruff format made changes
git add -A && git commit -m "chore: ruff format"
```
