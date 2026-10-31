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
  `ProcessManager` / `ServiceManager` keep their existing inputs (the tray reads
  `units`).
- **Old configs still load.** A config with `processes` / `services` and no
  `units` is read as `units = processes + services` (the previous visual order).
  The next save writes `units` only; keeping both keys would create two
  sources of truth. Per-unit `kind` is optional on read: a missing one is
  inferred from the unit's shape (`services` → service group, otherwise a
  process), so hand-edited files are forgiving; an unknown `kind` value is a
  corrupted config (backed up, as any other parse failure).
- **Order is the array.** No separate `dashboard_order` list: the units array is
  the order, so reorder is a list move, and add/delete are list operations.
  `services` / `processes` relative order inside the array is whatever the user
  dragged; nothing else reads that order for correctness.
- **Reorder moves by identity, not by index.** The screen turns a rendered drop
  position into the moved unit's kind + name and the unit that now follows it,
  then calls `SettingsViewModel.moveUnitBefore(kind, name, before:)`. That
  matters because the rendered order comes from
  `DashboardViewModel.unitsInOrder(settings.units)`, which can be shorter than
  `settings.units` by a card while a deleted unit is still in the dashboard
  view model. A unit the config no longer has is not rendered during that
  reload window (it is omitted, not parked at the end).
- **Reorder persists the order without reloading the managers.** A drag is a
  list move, so it writes the new `units` order and stops there: reloading
  would run the autostart path and could start a process the user stopped
  manually. The dashboard applies the newer order immediately through
  `DashboardViewModel.unitsInOrder`; the tray menu and the next reload of either
  manager follow the config. Nothing about a unit's running state changes.
- **Names are expected to be unique within a kind, not enforced.** The managers
  key controllers by name, so a hand-edited duplicate within a kind would
  collide; keys carry the kind prefix, so different kinds may share a label; a
  copy is renamed.
- **One dashboard view model.** `DashboardViewModel` owns both kinds' view
  models and rebuilds from `units`, so the dashboard has a single ordered
  `units` list of `DashboardUnit` (`ProcessUnit` / `ServiceUnit`).
  `ServicesViewModel` is
  deleted rather than kept as a second source of the same view models.
- **Cards keep their kind-specific body.** A process card shows the output
  preview; a service card shows the aggregate state plus per-service rows
  (`ServiceGridCard` is the compact grid tile: state, name, `N/M running`,
  toggle, edit). Both are dragged the same way.
- **The tray menu follows the same order** (units in config order, a separator
  only where the kind changes). Nothing notifies `TrayViewModel` on a reorder, so
  it follows the new order the next time the menu is rebuilt (any tray update, a
  config reload, or a restart), while the dashboard applies it immediately.
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
- `SettingsViewModel`: add/edit/delete/copy operate on unit indexes; reorder
  moves by kind + name through `moveUnitBefore` (no rendered index reaches
  `settings.units`). Every write persists the whole units array (globals carried
  too — the "a new global lands in three places" trap); a reorder uses the one
  write-only persist path, with no manager reload.
- `DashboardViewModel`: units follow config order, `unitsInOrder` follows a
  fresher settings order and omits units the config no longer has, view models
  are reused across reloads by (kind, name), removed units are disposed.
- `DashboardScreen`: mixed list and grid render in order, drag reorders across
  kinds by identity and persists, a unit deleted through settings disappears
  immediately (not parked at the end), "+" menu offers both kinds, service card
  opens the detail page, empty state only when there are no units.
- Tray: menu order follows units, keys stay `proc:` / `svc:`.

## Out of scope

- Per-service cards (the group is still the unit).
- Migrating `restart`/`autostart` semantics or the service poll interval.
- A resident elevated broker.
