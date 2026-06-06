# Fix Pre-Existing Type Errors — Design Spec

## Summary

Fix 16 selected pre-existing `mypy`/`ty` type errors across 5 source files. All are low-risk, purely mechanical changes (type annotations, `# type: ignore` comments, or dev dependency additions). No runtime behavior changes.

## Selection Criteria

Fixing errors in categories A-E and H (see below). Excluding categories F ("None" attribute access — requires init refactoring, medium risk) and G (lambda type inference — pure noise).

## Changes by Category

### Category A: `callable` → `Callable` (7 occurrences, 3 files)

Replace bare `callable` with `Callable[..., None]` (no arguments, no return). Python 3.11+ disallows `callable` as a type annotation.

**Files:**

| File | Line(s) | Change |
|---|---|---|
| `src/process_mgr.py` | 43-44 | `list[callable]` → `list[Callable[..., None]]` |
| `src/process_mgr.py` | 56 | `cb: callable` → `cb: Callable[..., None]` |
| `src/process_mgr.py` | 59 | `cb: callable` → `cb: Callable[..., None]` |
| `src/main_window.py` | 52 | `callable \| None` → `Callable[..., None] \| None` |
| `src/main_window.py` | 122 | `callback: callable` → `callback: Callable[..., None]` |
| `src/app_controller.py` | 46 | `-> callable` → `-> Callable[..., None]` |

Each file adds `from collections.abc import Callable` at top.

### Category B: Missing stubs `types-psutil`

Add `types-psutil` to dev dependencies:

```bash
uv add --dev types-psutil
```

### Category C: `PhotoImage` type mismatch (2 files)

tkinter stubs don't accept `PIL.ImageTk.PhotoImage` in `Wm.wm_iconphoto`. This is a stubs bug — ImageTk.PhotoImage IS valid at runtime. Suppress with `# type: ignore[arg-type]`.

| File | Line | Current | Change |
|---|---|---|---|
| `src/config_ui.py` | 24 | `self.dialog.iconphoto(True, self._tk_icon)` | Add `# type: ignore[arg-type]` |
| `src/main_window.py` | 26 | `self.root.iconphoto(True, self._tk_icon)` | Add `# type: ignore[arg-type]` |

### Category D: `Variable` → `StringVar` (1 file)

`_browse_dir(self, var: tk.StringVar)` called from lambda with `v["cwd"]` whose dict value type is `Variable`. `StringVar` is a subclass — runtime-safe. Suppress at call site.

| File | Line | Change |
|---|---|---|
| `src/config_ui.py` | 165 | Add `# type: ignore[arg-type]` on the `command=lambda:` line |

### Category E: `dict` → `AppConfig` (1 file, 2 locations)

The config dict built in `_on_save()` is structurally an `AppConfig` but inferred as `dict[str, object]`. Add explicit type annotation.

| File | Line | Change |
|---|---|---|
| `src/config_ui.py` | ~501 | Annotate config variable: `config: AppConfig = {...}` |
| `src/config_ui.py` | 18 (member) | Change `self._result: dict` → `self._result: AppConfig` |

### Category H: `ttk.Frame` → `ttk.LabelFrame` (1 file, 4 methods)

`_build_process_row` creates `ttk.LabelFrame`, not `ttk.Frame`. Change parameter types in 4 methods.

| File | Line | Method | Change |
|---|---|---|---|
| `src/config_ui.py` | 305 | `_copy_process(self, frame: ttk.Frame)` | → `ttk.LabelFrame` |
| `src/config_ui.py` | 324 | `_move_up(self, frame: ttk.Frame)` | → `ttk.LabelFrame` |
| `src/config_ui.py` | 335 | `_move_down(self, frame: ttk.Frame)` | → `ttk.LabelFrame` |
| `src/config_ui.py` | 346 | `_delete_process(self, frame: ttk.Frame)` | → `ttk.LabelFrame` |

## Risk Assessment

- All changes are type-annotation-only or `# type: ignore` comments
- Zero runtime code changes
- Zero test failures expected
- `types-psutil` is a stub-only package (no runtime code)
- Backward compatibility: no impact

## Files Changed

| File | Categories |
|---|---|
| `src/process_mgr.py` | A |
| `src/main_window.py` | A, C |
| `src/app_controller.py` | A |
| `src/config_ui.py` | C, D, E, H |
| `pyproject.toml` | B |

## Verification

After changes:
1. `uv run ruff format src/ && uv run ruff check src/`
2. `uv run mypy src/` — 16 fewer errors
3. `uv run ty check src/` — 16 fewer diagnostics
4. `uv run pytest tests/ -v` — 135 tests still pass
