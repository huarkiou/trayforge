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
        return os.path.join(config_home, "autostart", "TrayForge.desktop")

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
