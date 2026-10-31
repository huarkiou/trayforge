# Dashboard units: service groups in the card flow

Status: resolved
Type: task

## Problem

Service groups have their own page (ADR 005), so the dashboard shows only
processes: two places to look, two add paths, and no shared card order. The
config keeps `processes` and `services` in two arrays, so a mixed, reorderable
card flow has no single order to follow.

## Work

1. Model: `UnitConfig` sealed base with a `UnitKind get kind` (the enum owns
   the JSON value, display label and key prefix); `ProcessConfig` /
   `ServiceConfig` extend it; `AppConfig.units` is the ordered list,
   `processes` / `services` become derived getters. JSON writes one `units`
   array with a per-unit `kind`; `fromJson` migrates legacy `processes` +
   `services` (processes first), infers a missing `kind` from the unit's shape,
   and treats an unknown `kind` as a corrupted config.
2. `ConfigStore.validate(UnitConfig)` dispatches to the per-kind rules.
3. `SettingsViewModel`: one `_units` list; `addUnit` / `editUnit` / `deleteUnit`
   / `copyUnit` / `validateUnit` take unit indexes (or a `UnitConfig`) and
   persist the whole array (globals carried in `_save` and `_saveGlobals`).
   `reorderItem` persists the order only — a write-only save, with no manager
   reload, so a drag never runs the autostart path.
4. `DashboardViewModel`: owns process **and** service view models, exposes one
   ordered `units` list (`DashboardUnit` as `ProcessUnit` / `ServiceUnit`),
   reuses view models across reloads by kind + name, disposes the ones that
   disappeared. `ServicesViewModel` is deleted.
5. `DashboardScreen`: mixed list and grid rendering, long-press drag across
   kinds, "+" menu (Add process / Add service group), empty state keyed on
   units, service cards route to the service detail/edit pages. `ServicesPage`
   and its AppBar entry are deleted.
6. `ServiceGridCard`: compact grid tile for a service group.
7. `main`: drop `ServicesViewModel`, hand `ServiceManager` to
   `DashboardViewModel`.
8. Tray: menu order follows `units` (separator only on a kind change); keys
   stay `proc:` / `svc:`.
9. Docs: ADR 006 (supersedes ADR 005's "separate page" decision), ADR 005
   status note, `CONTEXT.md` glossary, `README.md` config example. The README
   change also fixes unit vocabulary, a stale bullet, and the file tree (it
   lists the real files, including the service adapters).
10. Tests: model migration/round-trip, settings unit operations and write-only
    reorder, dashboard units and screen behaviour (list and grid drag across
    kinds, group detail selectable members, crashed-group toggle), tray order,
    service grid card; migrate the deleted Services page coverage into the
    dashboard tests.

## Acceptance

- A service group card sits anywhere among the process cards, in both layouts,
  and dragging it there persists (`units` order) across a restart.
- Tapping it opens the group detail page, the edit icon opens the edit form.
- An old `config.json` with `processes` + `services` keeps working; the first
  save rewrites it as `units`.
- `dart format` / `dart analyze` clean, all tests pass, release build succeeds.
