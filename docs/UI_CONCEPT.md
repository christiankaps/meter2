# Meter2 UI Concept

## Summary

Meter2 should feel simple, modern, native, and calm. The interface should make everyday meter tracking fast while keeping advanced insights understandable and unobtrusive.

The app should avoid visual clutter, duplicated actions, and blocking workflows. Users should always understand what is happening, especially during imports, exports, calculations, or other operations that may take noticeable time.

## Design Principles

- Keep the interface simple, focused, and modern.
- Prefer native macOS controls, spacing, typography, menus, dialogs, and keyboard behavior.
- Use one clear visible path for each action instead of duplicating the same action across several places.
- Prefer direct manipulation for contextual work: click selects, double-click opens or edits, context menus reveal secondary actions, and the menu bar carries complete command access.
- Keep primary workflows close to the user's current context.
- Use concise labels and rely on recognizable macOS patterns instead of explanatory UI text.
- Keep charts and statistics readable at a glance.
- Use color intentionally to communicate meter type, status, forecast confidence, warnings, and chart meaning.
- Support both light and dark appearances cleanly.

## Interaction Model

Meter2 should feel like a native macOS utility, not a web dashboard with every action visible at once. Visible buttons should be reserved for the actions users need repeatedly or must discover immediately. Secondary and destructive actions should move into context menus, double-click behavior, or the menu bar when that creates a calmer and more native workflow.

Recommended interaction hierarchy:

1. Visible primary actions: create the first meter, add a reading to the selected meter, confirm/cancel modal workflows, and empty-state recovery actions.
2. Direct manipulation: single-click selects rows/cards, double-click opens edit for editable records, and Return confirms safe default actions.
3. Context menus: edit, delete, archive, export selected meter, print selected meter, copy values, and other item-specific commands.
4. Menu bar commands: complete command coverage for keyboard users and for less frequent global actions such as CSV import/export, report export/print, sync, update checks, and help.
5. Toolbar: a small set of high-frequency global or selected-context actions, never a full command palette.

Do not hide essential creation paths behind context menus only. Context menus should make expert workflows faster, not become the only way to complete a common task.

## Button Audit

The current direction should reduce always-visible buttons and lean harder on native macOS behavior.

Recommended visible controls:

| Area | Keep Visible | Move To Direct Action Or Context Menu | Notes |
| --- | --- | --- | --- |
| Sidebar | Add meter if the library is empty or as one small toolbar/sidebar action | Add reading per meter row can become a hover/context action if detail view has a clear Add Reading button | Avoid both a global Add Reading toolbar button and per-row plus buttons competing visually. |
| Dashboard meter cards | None beyond the card itself | Double-click opens the meter; context menu offers Add Reading, Edit Meter, Export Report | Cards should feel like selectable native items, not button-shaped controls. |
| Meter detail header | One primary Add Reading action | Edit Meter, Delete Meter, Archive/Unarchive, Export/Print selected meter | Editing metadata is secondary compared with recording readings. Delete should not live as a persistent toolbar button. |
| Reading history rows | No persistent edit/delete buttons | Double-click edits; context menu offers Edit and Delete; Delete key can delete with confirmation when allowed | Inline icon buttons on every row create visual noise and can make the history feel less native. |
| CSV import dialog | Cancel and Import | Column-specific actions stay in pickers/menus | Modal workflows need clear fixed actions; they should not depend on window chrome or hidden context menus. |
| Export/report/sync | Menu bar and compact toolbar menus only if frequently used | Context menu on selected meter for selected-scope exports/reports | Global toolbar should not become a command shelf. |

## Context Menus And Double-Click

Use context menus where the object under the pointer is the command target.

- Meter rows and dashboard cards: Add Reading, Edit Meter, Export Selected Meter CSV, Export Selected Meter Report, Print Selected Meter Report, Archive/Unarchive, Delete.
- Reading rows: Edit Reading, Delete Reading, Copy Value, Copy Date, Copy Reading Summary.
- Charts: Copy Chart Summary, export/copy image later if chart export becomes a real feature.
- Empty areas should not have broad context menus unless there is one obvious creation action.

Double-click behavior should be predictable:

- Double-click a meter row or dashboard card to open/select that meter.
- Double-click a reading row to edit that reading.
- Do not use double-click for destructive actions.
- Keep keyboard equivalents in the menu bar for every double-click action.

## Color Direction

The app can use more color, but it should be semantic and restrained. Meter2 tracks concrete real-world resources, so color can make scanning easier without turning the UI decorative.

Recommended color use:

- Meter kind tint: electricity, water, gas, heat, and custom meters should each have a subtle accent used in icons, cards, and chart marks.
- Status color: green for ready/healthy/importable, orange for warnings/duplicates/forecast uncertainty, red for invalid/destructive/failure, blue for neutral informational states.
- Chart color: reading value line, forecast line, consumption bars, and anomaly markers should use distinct stable colors.
- Sync color: neutral when idle/disabled, blue while syncing, orange offline, red failed.
- Avoid using color as the only signal; pair it with icons, labels, or shape.

The overall app should still feel calm. Prefer small color accents, tinted symbols, chart marks, and status chips over large saturated backgrounds.

## Workflow Audit

Core workflows should become more native and more obvious by reducing duplicated controls.

- Add first meter: should be unmistakable in the empty state and available from `Command-N`.
- Add reading: should be the dominant selected-meter action, available from the meter detail view, meter context menu, and `Command-Shift-N`.
- Edit meter: should be available through double-click/context menu/menu bar, not necessarily as a persistent toolbar button.
- Delete meter: should move away from persistent toolbar visibility and into context/menu flows with confirmation.
- Edit reading: double-click the reading row, or use context menu/menu command.
- Delete reading: context menu or Delete key with confirmation; avoid permanent trash buttons on every row.
- CSV import: keep as a menu bar command and optional compact toolbar command because it is global and file-based.
- CSV export and report export/print: use selected-object context menus and menu bar commands; keep toolbar presence only if user testing shows frequent use.
- Sync: a compact status/menu control is appropriate because sync state matters globally, but the menu should stay informational and sparse.
- Search: `Command-F` should focus the relevant visible search field; search should not appear where there is no searchable list.

## Intuitiveness Checks

Before implementing UI simplification, validate each workflow against these questions:

- Can a new user discover how to add the first meter without a context menu?
- Can a returning user add a reading in one obvious step from the selected meter?
- Does every hidden context-menu action also exist in the menu bar or through a standard keyboard path?
- Are destructive actions harder to trigger accidentally than constructive actions?
- Does a row with no visible buttons still communicate that it can be opened or edited?
- Does color help the user understand status or category, rather than merely decorating the screen?
- Can keyboard-only users complete the same workflow without pointer-only shortcuts?

## Responsiveness

The app must remain responsive during all user workflows.

- Do not run potentially heavy tasks on the main thread.
- Move imports, exports, parsing, forecasting, large calculations, file operations, and migration-like work off the main thread when they may block interaction.
- Keep UI state updates on the main actor and keep background work isolated from SwiftUI view updates.
- Prefer cancellable async work for long operations when cancellation would be useful to the user.
- Avoid loading or processing large data sets synchronously from view bodies.

## Progress And Feedback

Show progress feedback for tasks that may take noticeable time.

- Use a progress bar or progress indicator for potentially heavy tasks such as CSV import, CSV export, bulk validation, future report generation, or large data recalculations.
- Show determinate progress when the app can reasonably know total work.
- Use indeterminate progress only when total work is unknown.
- Keep progress feedback local to the current workflow, such as inside the import dialog or export sheet.
- Show clear success, warning, or failure results after the task completes.
- Never leave the user wondering whether an action is still running.

## Keyboard Navigation

Meter2 should support keyboard navigation as far as practical for a native macOS app.

- Support Tab and Shift-Tab through form fields and controls.
- Support arrow keys for navigating lists, tables, sidebars, segmented controls, and chart selections where appropriate.
- Use Return for the primary confirmation action in dialogs when safe.
- Use Escape to cancel dialogs, close transient UI, or dismiss non-destructive flows.
- Keep focus visible and predictable.
- Avoid keyboard traps where focus cannot leave a control or dialog.
- Make destructive actions require explicit confirmation and avoid accidental keyboard activation.

## Shortcuts

Keyboard shortcuts should cover frequent actions without overwhelming the app.

Recommended shortcuts:

| Shortcut | Action |
| --- | --- |
| `Command-N` | Add meter |
| `Command-Shift-N` | Add reading |
| `Command-I` | Import CSV |
| `Command-E` | Export CSV |
| `Command-F` | Focus search when a search field is available |
| `Command-,` | Open settings when settings exist |
| `Command-?` | Open app help |
| `Escape` | Cancel the current dialog or transient workflow |
| `Return` | Confirm the focused primary action when safe |
| `Arrow Up` / `Arrow Down` | Move through sidebar, meter list, tables, and menu-like controls |
| `Arrow Left` / `Arrow Right` | Move through segmented controls, chart selections, or horizontal navigation where appropriate |

Shortcuts should be implemented through native macOS command menus where possible so they appear in the menu bar and behave consistently with system expectations.

## App Help

Document keyboard shortcuts in the app's Help area.

- Add a Help entry for keyboard shortcuts once the app has an in-app help screen, help book, or equivalent native help surface.
- Keep shortcut documentation short and task-oriented.
- Include only shortcuts that are actually implemented.
- Update the Help documentation whenever shortcuts are added, removed, or changed.

## Accessibility

The UI should remain accessible while staying simple.

- Provide accessibility labels for icon-only controls.
- Preserve sufficient contrast in light and dark appearances.
- Respect Dynamic Type and system accessibility settings where native macOS APIs support them.
- Keep progress indicators accessible with meaningful labels.
- Ensure keyboard-only users can complete core workflows.

## Implementation Notes

- Prefer Swift concurrency for background work.
- Keep view bodies lightweight and avoid starting long-running work directly from view rendering.
- Use view models or services for import, export, analytics, and future report workflows when they become complex.
- Test heavy workflows with realistic data volumes before release.
- Add regression tests for parsing, calculation, and progress-state behavior when practical.
