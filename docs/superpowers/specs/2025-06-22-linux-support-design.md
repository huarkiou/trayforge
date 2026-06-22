# TrayForge Linux 支持设计

## 目标

在保持 Windows 功能不退化前提下，用最小改动让 TrayForge 在 Linux 上实现全功能对等。

## 约束

- 零新文件，不改架构
- 延续现有 `if sys.platform == "win32"` 分支模式
- ruff format + ruff check + mypy 零错误
- Python 3.11+

---

## 1. 进程管理 (`process_mgr.py`)

### 1.1 `_start()` — 创建子进程

Linux 上新增 `start_new_session=True`，使子进程成为 session leader（PGID==PID），为后续进程组杀做准备。

```python
if sys.platform != "win32":
    kwargs["start_new_session"] = True
```

**为何 `start_new_session` 而非 `preexec_fn=os.setsid`**：CPython C 层实现，无 fork 后线程安全问题。Python 3.2+ 可用。

### 1.2 `_stop_internal()` — 进程终止

Linux 用 `os.killpg` 杀整个进程组（等价 Windows `taskkill /t`），带运行时安全守卫。

```python
if sys.platform == "win32":
    subprocess.run(["taskkill", "/f", "/t", "/pid", str(pid)], ...)
else:
    try:
        if os.getpgid(pid) == pid:  # 安全守卫：确认是 session leader
            os.killpg(pid, signal.SIGTERM)
            try:
                ps.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(pid, signal.SIGKILL)
                ps.proc.wait(timeout=2)
        else:
            # 回退：不冒险杀错进程组
            ps.proc.terminate()
            try:
                ps.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                ps.proc.kill()
                ps.proc.wait(timeout=2)
    except ProcessLookupError:
        pass  # 已经死了
```

### 1.3 `_kill_cwd_processes()` — 杀同目录残留

Linux 用 `os.kill(pid, SIGKILL)` 代替 `taskkill`。

```python
if sys.platform == "win32":
    subprocess.run(["taskkill", "/f", "/t", "/pid", str(pid)], ...)
else:
    os.kill(pid, signal.SIGKILL)
```

顺带修复当前 bug：非 Windows 上也调 taskkill，静默异常被吞。

### 1.4 un-gate `cleanup_cwd` 和 `delete_before_start`

移除 `sys.platform == "win32"` 门控，Linux 也用这些功能。内部已按平台分支。

### 1.5 新增 import

```python
import signal
```

---

## 2. 单实例保护 (`single_instance.py`)

Linux 用 PID 文件 + `fcntl.flock` 排他锁。锁放在 `$XDG_RUNTIME_DIR/TrayForge/instance.lock`。

```python
if sys.platform == "win32":
    import ctypes
else:
    import fcntl

def _ensure_linux() -> bool:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    lock_dir = os.path.join(runtime_dir, "TrayForge")
    os.makedirs(lock_dir, exist_ok=True)
    lock_path = os.path.join(lock_dir, "instance.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_TRUNC, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (IOError, OSError):
        os.close(fd)
        return False
    os.write(fd, str(os.getpid()).encode())
    _ensure_linux._lock_fd = fd
    return True
```

**设计要点**：
- `$XDG_RUNTIME_DIR` 通常是 tmpfs，进程退出自动清理
- `flock` 内核级释放，崩溃也不残留死锁
- `LOCK_NB` 非阻塞，已锁立即返回 False

---

## 3. 开机自启 (`startup.py`)

API 不变，内部按平台分支。Linux 用 XDG autostart `.desktop` 文件。

| 函数 | Windows | Linux |
|------|---------|-------|
| `is_autostart_enabled()` | 读注册表 | `os.path.exists(desktop_path)` |
| `enable_autostart()` | 写注册表 | 写 `~/.config/autostart/TrayForge.desktop` |
| `disable_autostart()` | 删注册表键 | `os.remove(desktop_path)` |

`import winreg` 改为条件导入。`_get_exe_path()` 逻辑跨平台通用。

`.desktop` 文件内容：
```ini
[Desktop Entry]
Type=Application
Name=TrayForge
Exec=/usr/bin/env python /path/to/main.pyw
Hidden=false
X-GNOME-Autostart-enabled=true
```

---

## 4. 数据目录 (`config.py` + `logger.py`)

| 文件 | Windows | Linux |
|------|---------|-------|
| `config.py` `get_data_dir()` | `%LOCALAPPDATA%\TrayForge` | `$XDG_DATA_HOME/TrayForge` 或 `~/.local/share/TrayForge` |
| `logger.py` `_get_log_dir()` | `%LOCALAPPDATA%\TrayForge\logs` | `$XDG_STATE_HOME/TrayForge/logs` 或 `~/.local/state/TrayForge/logs` |

各函数顶部加 3 行分支，不改签名。`TRAYFORGE_DATA_DIR` 环境变量覆盖逻辑不变。

---

## 5. 设置界面 (`config_ui.py`)

Autostart checkbox 文案改为平台中性：

```python
text="Start TrayForge on login"
```

---

## 6. 测试适配

### `tests/conftest.py`

fixture 补充 `max_restarts` 字段（`ProcessConfig` TypedDict 要求）。

### `tests/test_startup.py`

类级别加 `@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")`。

---

## 改动量汇总

| 文件 | 行数 | 类型 |
|------|------|------|
| `process_mgr.py` | ~35 | 逻辑 |
| `single_instance.py` | ~25 | 重写 |
| `startup.py` | ~40 | 重写 |
| `config.py` | ~4 | 分支 |
| `logger.py` | ~4 | 分支 |
| `config_ui.py` | ~1 | 文案 |
| `tests/conftest.py` | ~2 | 补字段 |
| `tests/test_startup.py` | ~2 | skipif |
| **合计** | **~113** | **零新文件** |

## 验证清单

- [ ] `ruff format src/ tests/` 通过
- [ ] `ruff check src/ tests/` 通过
- [ ] `mypy src/` 通过
- [ ] Windows 功能无退化（GUI + headless + CLI）
- [ ] Linux `--headless` 模式可用
- [ ] Linux GUI 模式可用（需要 display）
- [ ] Linux 单实例保护生效
- [ ] Linux 进程组杀生效
