"""TrayForge - tray controller for managed processes."""

import sys
import os
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from single_instance import ensure_single_instance
from logger import get_main_logger
from config import load_config, get_default_config, save_config
from process_mgr import ProcessManager
from main_window import MainWindow
from tray_ui import TrayUI
from app_controller import AppController


def _log_unhandled(exc_type, exc_value, exc_tb, thread_name="main"):
    logger = get_main_logger()
    logger.critical(
        "Unhandled exception in %s thread",
        thread_name,
        exc_info=(exc_type, exc_value, exc_tb),
    )


def main() -> None:
    logger = get_main_logger()

    sys.excepthook = lambda *a: _log_unhandled(*a)
    threading.excepthook = lambda args: _log_unhandled(
        args.exc_type, args.exc_value, args.exc_traceback, args.thread.name
    )

    if not ensure_single_instance():
        logger.warning("TrayForge is already running, exiting")
        try:
            import tkinter.messagebox

            tkinter.messagebox.showwarning("TrayForge", "TrayForge is already running.")
        except Exception:
            pass
        return

    logger.info("=" * 40)
    logger.info("TrayForge starting...")

    window = MainWindow()

    is_first = load_config() is None
    config = get_default_config() if is_first else load_config()
    if is_first:
        save_config(config)  # ty:ignore[invalid-argument-type]

    pm = ProcessManager(config)  # ty:ignore[invalid-argument-type]
    tray = TrayUI(pm, window, config)  # ty:ignore[invalid-argument-type]
    window.set_processes(pm.process_names())

    app = AppController(config, pm, window, tray)
    app.start(is_first)


if __name__ == "__main__":
    if "--headless" in sys.argv:
        from headless_controller import run_headless

        run_headless()
    elif len(sys.argv) > 1:
        from cli import main as cli_main

        sys.exit(cli_main())
    else:
        main()
