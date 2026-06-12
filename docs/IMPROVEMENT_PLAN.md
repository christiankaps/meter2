# Meter2 Improvement Plan

Plan created 2026-06-10 from a comparison of `docs/APP_CONCEPT.md`, `docs/UI_CONCEPT.md`, `docs/REQUIREMENTS.md`, and the current implementation. Work items should be executed directly on `main` following `AGENTS.md`.

## Current State Assessment

The macOS MVP scope is essentially complete: meter and reading management, validation, statistics with advanced time scoping, deterministic forecasting, tariffs and billing periods, CSV import/export, PDF reports, localization, in-app updates, and a GitHub release pipeline are all implemented and covered by roughly 110 unit tests.

The main gaps are:

1. **In-progress committed scope is unfinished.** iCloud sync, the iPhone companion, and shared household collaboration are all marked `In Progress`. The CloudKit sync foundation (`MeterLibrarySync.swift`) and companion views exist, but runtime CloudKit behavior is unverified because it requires a signed developer build (lesson 2026-05-13).
2. **`ContentView.swift` is a 2,800-line monolith.** All macOS UI lives in one file, which makes reviews slower, increases merge risk, and conflicts with the UI concept's recommendation to use view models or services for complex workflows.
3. **Concept features without requirements entries.** The app concept describes a readings view with search, filtering, and sorting, plus outlier/anomaly surfacing; neither is implemented or tracked in `REQUIREMENTS.md`.
4. **Open product questions are still open.** Six questions in `APP_CONCEPT.md` (interval meters, meter replacement modeling, tiered tariffs, reminders in MVP, export scope) have de-facto answers in the shipped app but were never recorded as decisions.

## Phase 1 — Maintainability Foundation (Done 2026-06-10)

Goal: make future feature work cheaper and safer without changing behavior.

- Split `ContentView.swift` into focused files per feature area (sidebar/navigation, dashboard, meter detail, statistics cards, reading forms, settings/appearance, import/export sheets). Pure file moves first, no logic changes.
- Split `Meter2Tests.swift` along the same feature boundaries so test ownership stays obvious.
- Verify after the split that `make build` and `make test` pass and no view behavior changed.

## Phase 2 — Finish Committed In-Progress Scope

Goal: move the three `In Progress` requirements to `Implemented` or consciously re-scope them.

- Verify CloudKit sync end to end in a signed Apple Developer build (the known blocker). Document the result as a lesson learned.
- Complete the opt-in sync enablement flow on macOS: explicit user consent, migration of existing local data, clear sync status, and a safe disable path.
- Bring the iPhone companion to its first usable milestone: meter overview, fast reading capture, reading correction, and sync status — nothing more, per the focused-companion requirement.
- Implement collaboration milestone 1 via CloudKit sharing: owners manage meters/tariffs/billing/sharing; collaborators add and edit readings.
- If signed-build verification reveals sync is not viable soon, downgrade these requirements to `Deferred` with a recorded reason instead of leaving them `In Progress` indefinitely.

## Phase 3 — Close Concept Gaps On macOS (Done 2026-06-10)

Goal: deliver the concept-described capabilities that the MVP skipped, in order of daily-use value.

- Done: inline reading-history search filtering by note, value, and date text (meter selection in the sidebar already covers per-meter filtering; the statistics scope covers date ranges).
- Done: unusual-usage surfacing in meter detail via median daily-rate anomalies with plain-language explanations.
- Done: accessibility audit — charts already exposed textual summaries and icon-only controls were labeled; the gap was keyboard access to search.
- Done: `Command-F` focuses the reading search and is documented in the shortcuts help.
- Done: delivered items recorded in `REQUIREMENTS.md`.

## Phase 4 — Product Depth (Currently Deferred)

Goal: revisit deferred features once Phases 2–3 land. Re-evaluate priority then; do not start these earlier.

- Reading reminders (likely first: high recurring value, low complexity).
- Advanced tariff models (tiered pricing).
- Photo attachments and OCR-assisted capture.
- JSON backup format.

## Phase 5 — Mac-Native Interaction Refinement

Goal: turn the revised UI concept into a calmer macOS workflow with fewer persistent buttons, stronger direct manipulation, complete menu access, and restrained semantic color.

Guiding rules:

- Keep one obvious visible path for core creation tasks.
- Move secondary item-specific actions to context menus, double-click, keyboard shortcuts, and menu bar commands.
- Do not make context menus the only path for essential first-use workflows.
- Keep every hidden pointer action reachable by keyboard or menu bar.
- Use color as information, not decoration.

### Task List

1. **Inventory current commands and visible controls.**
   - List every visible toolbar, sidebar, card, row, menu, and inline action.
   - Mark each action as primary, secondary, destructive, global, or object-specific.
   - Identify duplicated action paths that currently compete visually.
   - Deliverable: update this plan or `docs/UI_CONCEPT.md` with the final command inventory if implementation choices change.

2. **Define command routing in one place.**
   - Extend `Meter2CommandActions` or an equivalent command model so menu bar, toolbar, context menus, and keyboard shortcuts call the same actions.
   - Add selected-meter and selected-reading command availability where needed.
   - Keep disabled states consistent across all command surfaces.
   - Verification: unit-test pure command availability helpers if they become non-trivial.

3. **Add meter context menus.**
   - Add context menus to sidebar meter rows and dashboard meter cards.
   - Include Add Reading, Edit Meter, selected-meter CSV export, selected-meter report export, selected-meter print, Archive/Unarchive when available, and Delete.
   - Keep destructive Delete behind the existing confirmation flow.
   - Ensure collaborator permission states disable unavailable owner-only commands.
   - Verification: build, fast review, non-UI tests; manually inspect menu contents in the running app.

4. **Add direct manipulation for meters.**
   - Single-click should continue to select/open the meter.
   - Double-click a sidebar meter row or dashboard card should open the edit-meter flow only if this feels native after manual inspection; otherwise use double-click to open/select and keep edit in context/menu commands.
   - Preserve keyboard navigation in the sidebar and dashboard.
   - Verification: manual app check for single-click, double-click, and keyboard focus behavior.

5. **Simplify the main toolbar.**
   - Keep a small primary action surface: Add Meter when useful, Add Reading for the selected meter, and compact global status/menu controls where justified.
   - Remove persistent toolbar Delete Meter and Edit Meter buttons from the detail view if their context/menu paths are implemented.
   - Reassess whether CSV import/export and report menus belong in the toolbar or only in the Data/menu/context surfaces.
   - Verification: compare the toolbar against the button audit in `docs/UI_CONCEPT.md`.

6. **Refine reading history interactions.**
   - Remove always-visible edit and delete icon buttons from each reading row.
   - Add a reading-row context menu with Edit Reading, Delete Reading, Copy Value, Copy Date, and Copy Reading Summary.
   - Add double-click to edit a reading.
   - Add Delete-key handling for the selected/focused reading only if selection state is clear and confirmation remains explicit.
   - Verification: test row layout with long notes and German text; manually verify context menu and double-click behavior.

7. **Complete menu bar command coverage.**
   - Add menu commands for selected meter edit/delete/export/report/print where missing.
   - Add reading edit/delete commands when a reading selection exists.
   - Keep global commands for Add Meter, Add Reading, CSV import/export, sync, update check, and help.
   - Ensure shortcuts shown in Help match implemented commands.
   - Verification: update shortcut help only when command behavior changes.

8. **Introduce semantic meter colors.**
   - Define a small color mapping for meter kinds: electricity, water, gas, heat, and custom.
   - Apply subtle tints to meter icons, dashboard cards, and selected chart marks.
   - Ensure color survives light/dark mode and does not replace labels or symbols.
   - Verification: inspect light and dark appearances; keep contrast accessible.

9. **Strengthen chart and status color semantics.**
   - Keep stable chart colors for actual readings, forecasts, consumption bars, and anomalies.
   - Apply sync status colors to the sync menu symbol or compact status indicator.
   - Align CSV import preview statuses with green/orange/red/blue semantics.
   - Verification: compare status colors across dashboard, detail, CSV import, and sync surfaces.

10. **Validate first-use and keyboard-only workflows.**
    - Confirm a new user can add the first meter without context menus.
    - Confirm a returning user can add a selected-meter reading in one obvious step.
    - Confirm edit/delete/export/report remain discoverable through menu bar and context menus.
    - Confirm `Command-F`, `Command-N`, `Command-Shift-N`, `Command-I`, `Command-E`, Escape, Return, and arrow navigation behave consistently.
    - Deliverable: add a Lessons Learned entry if manual validation reveals a confusing workflow.

### Suggested Implementation Order

1. Command routing and menu bar coverage.
2. Meter context menus and direct manipulation.
3. Reading history context menus and row cleanup.
4. Toolbar simplification.
5. Semantic color system.
6. Manual workflow validation and documentation cleanup.

### Release Criteria

- The app has fewer persistent icon buttons than before, especially in reading rows and destructive meter actions.
- Add Meter and Add Reading remain obvious and fast.
- Secondary commands are available from context menus and menu bar commands.
- Keyboard users can complete equivalent workflows without pointer-only shortcuts.
- Semantic color improves scanning without reducing accessibility.
- `docs/UI_CONCEPT.md` and `docs/REQUIREMENTS.md` match the delivered behavior.

## Housekeeping

- Done 2026-06-10: the open product questions in `APP_CONCEPT.md` are recorded as explicit product decisions.
- Keep `REQUIREMENTS.md` and the Lessons Learned table updated as each phase lands, per `AGENTS.md`.
