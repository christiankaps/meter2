# Meter2 UI Concept

## Summary

Meter2 should feel simple, modern, native, and calm. The interface should make everyday meter tracking fast while keeping advanced insights understandable and unobtrusive.

The app should avoid visual clutter, duplicated actions, and blocking workflows. Users should always understand what is happening, especially during imports, exports, calculations, or other operations that may take noticeable time.

## Design Principles

- Keep the interface simple, focused, and modern.
- Prefer native macOS controls, spacing, typography, menus, dialogs, and keyboard behavior.
- Use one clear visible path for each action instead of duplicating the same action across several places.
- Keep primary workflows close to the user's current context.
- Use concise labels and rely on recognizable macOS patterns instead of explanatory UI text.
- Keep charts and statistics readable at a glance.
- Support both light and dark appearances cleanly.

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
