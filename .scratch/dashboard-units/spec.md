# Dashboard units: service groups in the card flow

**Status:** ready-for-agent
**Date:** 2026-10-31

## Problem

Service groups live on their own page (ADR 005), so the dashboard only shows
processes. A user who manages both kinds has two places to look, two "+"
buttons, and no way to arrange the cards they actually watch in the order they
watch them. The split was a deliberate shortcut: two kinds in one reorderable
list need one ordering, and the config had two separate arrays with no shared
order.

## Solution

Make the dashboard a single ordered flow of **units**, where a unit is either a
process or a service group:

- `AppConfig.units` is one ordered list of `UnitConfig` (`ProcessConfig` or
  `ServiceConfig`), persisted as `units` in `config.json`.
- The dashboard renders the units in config order in both layouts (list cards
  and grid tiles) and one long-press drag reorders across kinds.
- The Services page, its `ServicesViewModel`, and the AppBar `dns` entry go
  away: the dashboard owns both kinds, "+" becomes a menu, and the service
  group's detail/edit pages stay as they are.

## Design decisions

- **One ordered array, one kind discriminator.** `UnitConfig` is the sealed base
  of `ProcessConfig` and `ServiceConfig` (both already have `name`). JSON is
  flat: `{"kind": "process", ...}` / `{"kind": "service", ...}` inside `units`.
  No wrapper objects, no `kind` field leaking into the per-kind config classes.
  `AppConfig.processes` / `.services` remain as derived getters so
  `ProcessManager` / `ServiceManager` and the tray keep their existing inputs.
- **Old configs still load.** A config with `processes` / `services` and no
  `units` is read as `units = processes + services` (the previous visual order).
  The next save writes `units` only; keeping both keys would create two
  sources of truth. Per-unit `kind` is optional on read: a missing one is
  inferred from the entry's shape (`services` → service group, otherwise a
  process), so hand-edited files are forgiving; an unknown `kind` value is a
  corrupted config (backed up, as any other parse failure).
- **Order is the array.** No separate `dashboard_order` list: the units array is
  the order, so reorder is a list move, and add/delete are list operations.
  `services` / `processes` relative order inside the array is whatever the user
  dragged; nothing else reads that order for correctness.
- **One dashboard view model.** `DashboardViewModel` owns both kinds' view
  models and rebuilds from `units`, so the dashboard has a single ordered
  `entries` list of `ProcessEntry` / `ServiceEntry`. `ServicesViewModel` is
  deleted rather than kept as a second source of the same view models.
- **Cards keep their kind-specific body.** A process card shows the output
  preview; a service card shows the aggregate state plus per-service rows
  (`ServiceGridCard` is the compact grid tile: state, name, `N/M running`,
  toggle, edit). Both are dragged the same way.
- **The tray menu follows the same order** (units in config order, a separator
  only where the kind changes), so the menu and the dashboard cannot disagree.
- **Unchanged on purpose**: process and service managers, the elevation path,
  the detail pages, the toggle rules, the tray colour (still processes only),
  and no autostart for service groups.

## Config shape

```json
{
  "output_history_limit": 1000,
  "output_refresh_ms": 500,
  "service_poll_ms": 5000,
  "dashboard_layout": "list",
  "units": [
    {"kind": "process", "name": "ComfyUI", "cmd": "python main.py"},
    {"kind": "service", "name": "LicenseSvcs", "services": ["ANSYS FlexNet"], "stop_dependents": true}
  ]
}
```

## Testing decisions

- Model round-trip: `units` order preserved, kinds round-trip, legacy
  `processes` + `services` migrated in order, kind inferred when missing,
  unknown kind treated as corrupted.
- `SettingsViewModel`: add/edit/delete/copy/reorder operate on unit indexes and
  persist the whole units array (globals carried too — the "a new global lands
  in three places" trap).
- `DashboardViewModel`: entries follow config order, view models are reused
  across reloads by (kind, name), removed units are disposed.
- `DashboardScreen`: mixed list and grid render in order, drag reorders across
  kinds and persists, "+" menu offers both kinds, service card opens the
  detail page, empty state only when there are no units.
- Tray: menu order follows units, keys stay `proc:` / `svc:`.

## Out of scope

- Per-service cards (the group is still the unit).
- Migrating `restart`/`autostart` semantics or the service poll interval.
- A resident elevated broker.
