# TrayForge Linux 支持设计

## 目标

在保持 Windows 功能不退化前提下，用最小改动让 TrayForge 在 Linux 上实现全功能对等。

## 约束

- 零新文件，不改架构
- 延续现有 `if sys.platform == "win32"` 分支模式
- ruff format + ruff check + mypy 零错误
- Python 3.11+

## 依赖

### Linux GUI 模式额外依赖

`pystray` 在 Linux 上需要系统托盘后端。各发行版包名：

| 发行版 | 包 |
|--------|----|
| Arch | `libayatana-appindicator` |
| Debian/Ubuntu | `gir1.2-ayatanaappindicator3-0.1` |
| Fedora | `libayatana-appindicator` |

纯 headless 模式（`--headless`）无需此依赖。

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

**已知局限**：`os.killpg` 的 `getpgid` 检查存在 TOCTOU 竞态（进程在检查和 killpg 之间退出、PGID 被复用）。概率极低，且最坏情况只是误杀一个刚创建的不相关进程组，实际影响可忽略。

### 1.3 `_kill_cwd_processes()` — 杀同目录残留

Linux 用 `os.kill(pid, SIGKILL)` 代替 `taskkill`。

```python
if sys.platform == "win32":
    subprocess.run(["taskkill", "/f", "/t", "/pid", str(pid)], ...)
else:
    os.kill(pid, signal.SIGKILL)
```

顺带修复当前 bug：非 Windows 上也调 taskkill，静默异常被吞。

**已知局限**：Linux 只杀匹配进程自身，不杀子进程（Windows `taskkill /t` 杀全树）。`cleanup_cwd` 清理不彻底时可能留下孤儿子进程。对 `delete_before_start` 场景（仅需解除文件占用）足够。

### 1.4 un-gate `cleanup_cwd` 和 `delete_before_start`

移除 `sys.platform == "win32"` 门控，Linux 也用这些功能。内部已按平台分支。

### 1.5 新增 import

```python
import signal
```

`signal` 模块在所有平台可用。

---

## 2. 单实例保护 (`single_instance.py`)

Linux 用 PID 文件 + `fcntl.flock` 排他锁。锁放在数据目录：

```
$XDG_DATA_HOME/TrayForge/instance.lock
或 ~/.local/share/TrayForge/instance.lock
```

```python
# 新增 import（文件顶层已有 import os）
import fcntl  # 条件导入：仅非 Windows

def _ensure_linux() -> bool:
    # 复用 get_data_dir() 获取数据目录
    from config import get_data_dir
    data_dir = get_data_dir()
    lock_path = os.path.join(data_dir, "instance.lock")
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
- 放在数据目录（`$XDG_DATA_HOME`），兼容性最好
- `flock` 内核级释放，崩溃/SIGKILL 也不残留死锁
- `LOCK_NB` 非阻塞，已锁立即返回 False
- `flock` 对 NFS 不生效，本地桌面应用可忽略

---

## 3. 开机自启 (`startup.py`)

API 不变，内部按平台分支。Linux 用 XDG autostart `.desktop` 文件。

| 函数 | Windows | Linux |
|------|---------|-------|
| `is_autostart_enabled()` | 读注册表 | `os.path.exists(desktop_path)` |
| `enable_autostart()` | 写注册表 | 写 `.desktop`（先写临时文件再 rename） |
| `disable_autostart()` | 删注册表键 | `os.remove(desktop_path)` |

**关键实现细节**：
- `import winreg` 改为 `if sys.platform == "win32"` 条件导入
- `.desktop` 路径：`$XDG_CONFIG_HOME/autostart/TrayForge.desktop`，fallback `~/.config/autostart/TrayForge.desktop`
- `_get_exe_path()` 跨平台通用（frozen → `sys.executable`；dev → `sys.executable` + 脚本路径），Linux 实现直接复用
- 写入前创建 `autostart/` 目录，原子写入（临时文件 + `os.rename`）
- 所有函数返回 `bool`，内部吞异常，不抛到上层

`.desktop` 文件内容：
```ini
[Desktop Entry]
Type=Application
Name=TrayForge
Exec={exe_path}
Terminal=false
StartupNotify=false
Hidden=false
```

其中 `{exe_path}` 由 `_get_exe_path()` 生成。

**注意**：`startup.py` 的条件导入必须在测试适配之前完成，否则 `tests/test_startup.py` 和 `tests/test_config_ui.py` 无法在 Linux 上 import。

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

fixture 补充 `cleanup_cwd` 和 `max_restarts` 字段（`ProcessConfig` TypedDict 要求）。

### `tests/test_process_mgr.py`

`_make_config()` 和内联 dict 补充 `cleanup_cwd` 字段。

### `tests/test_startup.py`

所有类加 `@pytest.mark.skipif(sys.platform != "win32", reason="Windows registry")`。

**前置条件**：`startup.py` 必须已完成条件导入改造（第 3 节），否则此文件无法在 Linux 上 import。

### `tests/test_config_ui.py`

已有对 `is_autostart_enabled` 的 patch，`startup.py` 可 import 后无需额外改动。

---

## 改动量汇总

| 文件 | 行数 | 类型 |
|------|------|------|
| `process_mgr.py` | ~35 | 逻辑 |
| `single_instance.py` | ~25 | 重写 |
| `startup.py` | ~50 | 重写 |
| `config.py` | ~4 | 分支 |
| `logger.py` | ~4 | 分支 |
| `config_ui.py` | ~1 | 文案 |
| `tests/conftest.py` | ~4 | 补字段 |
| `tests/test_process_mgr.py` | ~8 | 补字段 |
| `tests/test_startup.py` | ~2 | skipif |
| **合计** | **~133** | **零新文件** |

## 验证清单

- [ ] `ruff format src/ tests/` 通过
- [ ] `ruff check src/ tests/` 通过
- [ ] `mypy src/` 通过
- [ ] Windows 功能无退化（GUI + headless + CLI）
- [ ] Linux `--headless` 模式可用
- [ ] Linux GUI 模式可用（需安装 pystray 后端 + display）
- [ ] Linux 单实例保护生效
- [ ] Linux 进程组杀生效
