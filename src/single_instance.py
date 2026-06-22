"""Single-instance enforcement — named mutex (Windows) or PID file + fcntl (Linux)."""

import os
import sys

if sys.platform == "win32":
    import ctypes

    MUTEX_NAME = "Global\\TrayForge_SingleInstance"

    def _ensure_impl() -> bool:
        kernel32 = ctypes.windll.kernel32
        kernel32.CreateMutexW(None, True, MUTEX_NAME)
        return kernel32.GetLastError() != 183  # ERROR_ALREADY_EXISTS

else:
    import fcntl

    def _ensure_impl() -> bool:
        """Acquire an exclusive fcntl lock on a PID file in the data directory."""
        from config import get_data_dir

        lock_path = os.path.join(get_data_dir(), "instance.lock")
        try:
            fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_TRUNC, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.write(fd, str(os.getpid()).encode())
            _ensure_impl._lock_fd = fd  # type: ignore[attr-defined]
            return True
        except (IOError, OSError):
            try:
                os.close(fd)
            except Exception:
                pass
            return False


def ensure_single_instance() -> bool:
    """Try to acquire a system-wide lock. Returns True if we're the only instance."""
    return _ensure_impl()
