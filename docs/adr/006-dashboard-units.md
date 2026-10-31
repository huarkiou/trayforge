# ADR 006: Dashboard units — one ordered list for both kinds

**Status:** Accepted
**Date:** 2026-10-31
**Supersedes:** the "A separate page" decision in
[ADR 005](005-native-service-management.md)

## Context

ADR 005 gave service groups their own page and predicted the next step: unify
processes and services into one ordered `units` array if mixed ordering was ever
wanted. It was, for a simple reason: the dashboard is where a user watches and
operates everything, and a service group that only exists behind an AppBar icon
is a second place to look, a second add button, and a second ordering.

Mixing the two kinds in one reorderable list needs one order. The config had
two arrays (`processes`, `services`) with no shared position, so the visual
order was always "all processes, then all services" — a constant, not a choice.

## Decision

1. **`AppConfig.units` is the order.** One list of `UnitConfig`, whose only two
   implementations are `ProcessConfig` and `ServiceConfig` (both already carry
   `name`). Reordering the dashboard moves a unit in this list; there is no
   second layout array to keep in sync. `AppConfig.processes` and `.services`
   survive as derived getters, so `ProcessManager` and `ServiceManager` keep
   their existing inputs.
2. **The kind is written by `AppConfig`; the classes compute it.** JSON is flat
   with a discriminator: `{"kind": "process", ...process fields...}` /
   `{"kind": "service", ...group fields...}` inside `units`. `AppConfig.toJson`
   adds `kind` from `unit.kind.jsonValue`; `UnitConfig.toJson` contributes only
   the per-kind fields. The kind is not stored: `UnitConfig` declares a computed
   `UnitKind get kind`, and each subclass overrides it. Nothing kind-specific
   leaks into the sibling class.
3. **Old configs migrate on read, not on write.** A file with `processes` +
   `services` and no `units` loads as units in the old visual order (processes
   first). The next save writes `units` only: keeping both spellings would be
   two sources of truth. A unit without `kind` is inferred from its shape
   (`services` → group, else process), so hand-edited files stay forgiving; an
   unknown `kind` is treated like any other parse failure (the file is backed
   up).
4. **One dashboard view model.** `DashboardViewModel` owns both kinds' view
   models and exposes one ordered `units` list of `DashboardUnit`
   (`ProcessUnit` / `ServiceUnit`). `ServicesViewModel` is deleted rather than
   kept as a second producer of the same view models.
5. **Cards keep their kind-specific body.** A process card previews output; a
   group card lists members; the grid gets a compact `ServiceGridCard` beside
   `ProcessGridCard` so both layouts stay consistent. Every card follows its
   view model (the group card and its toggle listen themselves — the dashboard
   does not wrap each card in a rebuild).
6. **The tray lists units in the same order**, with a separator where the kind
   changes. It reads `units` when the menu is built, so it follows the dashboard
   order the next time the menu is rebuilt (any tray update, a config reload, or
   a restart); a drag itself is not pushed to the tray.
7. **The Services page is gone.** Cards are added, edited, reordered and opened
   from the dashboard; the `+` menu offers "Add process" / "Add service group",
   and the welcome screen (shown only when there is nothing at all) offers both.

## Consequences

- One ordering story end to end: dashboard drag → `units` → tray menu. A
  reorder persists the new order and does **not** reload the managers — a
  reload would run the autostart path and could start a process the user
  stopped by hand. The dashboard applies the newer order immediately by reading
  the `settings.units` order through `DashboardViewModel.unitsInOrder`. Nothing
  notifies `TrayViewModel` on a reorder, so the tray follows the same order the
  next time its menu is rebuilt (any tray update, a config reload, or a
  restart); the next reload of either manager also reads the config.
- Config writes are simpler (one array). Names are expected to be unique within
  a kind, not enforced: the managers key controllers by name, so a hand-edited
  duplicate within a kind would collide; keys carry the kind prefix, so
  different kinds may share a label; a copy is renamed.
- `ProcessManager` / `ServiceManager` are untouched: the derived getters hand
  each one its own kind in dashboard order.
- Fewer files (`services_page.dart`, `services_viewmodel.dart` and their tests
  are deleted); the group card's coverage moved into the dashboard tests.

## Alternatives rejected

- **Keep the separate page and also show cards on the dashboard.** Two places
  to look, two add paths, two orderings for the same data.
- **A separate `dashboard_order` reference list next to the two arrays.** Keeps
  the old schema but turns one order into two (array order vs. reference
  order), and needs add/delete/rename bookkeeping in both.
- **Interleave by an `order` integer on each unit.** Sparse, collision-prone,
  and drag becomes a renumbering exercise instead of a list move.
