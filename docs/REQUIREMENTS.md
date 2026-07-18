# Meter2 Requirements

This file is the shared product requirements record for requested, planned, deferred, rejected, and implemented Meter2 features.

## Feature Requirements

| Feature | Status | Notes |
| --- | --- | --- |
| Native macOS app | Implemented | The app uses a native SwiftUI macOS project. |
| Main window lifecycle | Implemented | Meter2 uses one main application window. Closing it terminates the app completely, even if an auxiliary About window is open, so it does not remain active in the Dock. |
| Modern app icon for Light, Dark, and Tinted themes | Implemented | Icon variants are included in the asset catalog. |
| Appearance mode selection | Implemented | Users can choose System, Light, or Dark appearance from one toolbar menu; System follows the current macOS appearance. |
| Bilingual user interface | Implemented | User-facing strings are localized for English and German. |
| Local-only data storage | Implemented | Meter data is stored locally with SwiftData. Meter2 explicitly saves every meter, reading, archive, delete, and CSV import mutation; failed saves are rolled back and surfaced to the user. Meter2 has no cloud storage, synchronization, or network dependency for meter data. |
| Example data | Implemented | The Data menu can load a localized, deterministic set of electricity, water, and gas meters with one year of readings. Loading is idempotent and restores only missing examples. A confirmed delete action removes only records identified as example data and never user-created meters. |
| Manual cumulative meter readings | Implemented | Users can create meters and enter timestamped readings manually. |
| Meter management | Implemented | Users can create, edit, archive, and delete meters. |
| Virtual meters | Implemented | Users can define a calculated meter as a signed combination of one or more existing manual meters, such as total solar production minus grid feed-in to show self-consumption. Virtual readings are derived through interpolation over shared source coverage and are never stored as independent measurements. |
| Reading management | Implemented | Users can create, edit, and delete manual readings. |
| Date-only readings | Implemented | Readings can store either a date-only value or a date-time value and display date-only readings without a time. |
| Reading validation | Implemented | Negative values and duplicate timestamps are blocked; lower readings, future dates, and unusually large jumps produce warnings. |
| Reading entry input state | Implemented | New reading forms start with the date field, infer date-only versus date-time from the typed value, keep a visible time-detail control for clarity, keep the value field empty, support compact date input such as `01062026`, allow `+` and `-` day stepping, and hide non-blocking warnings while the value is actively being typed. |
| Dashboard | Implemented | The dashboard summarizes active meters, readings, and forecasts in a compact adaptive overview, followed by meter cards that show identity, location, latest reading, and recency. Its first-use empty state provides a direct Add Meter action. |
| Meter detail view | Implemented | Meter detail includes insights, charts, forecasts, and reading history. Header metadata and custom date controls adapt vertically when horizontal space is constrained. |
| Period-based statistics | Implemented | Meter detail statistics use equal-size summary cards for consumption, like-for-like previous-period comparison, daily average, and deterministic projection; detailed forecast basis, cost, quality, and next-reading guidance remain available below the primary metrics. |
| Advanced statistics time scoping | Implemented | Statistics and charts support current month, current year, last 12 months, custom date ranges, previous months, previous years, and same months in previous years. In-progress periods compare only the equivalent elapsed part of the previous period; completed and custom periods compare against the corresponding previous range. |
| Aggregated period overviews | Implemented | Weekly, monthly, and yearly statistics show average consumption across the selected covered periods while keeping comparable period boundaries explicit. |
| Consumption charts | Implemented | Usage-over-time charts use aggregated consumption bars with a muted previous-period series; cumulative meter readings and forecast continuation remain available as separate readable diagrams. |
| Forecasting | Implemented | Forecasts use the same deterministic projection engine as the statistics cards, preferring the current period, then recent readings, then historical average, and explain basis, data window, and quality. |
| Simple tariff and billing support | Implemented | Optional flat unit price, base fee, currency code, and billing periods are supported. |
| CSV export | Implemented | Users can export all readings or the selected meter's readings as reimport-friendly long CSV files. CSV column headers intentionally remain stable English interchange labels regardless of app language. |
| CSV import | Implemented | Users can import wide or long CSV files through a mapping preview, skip duplicates, import valid rows, create missing meters in the import dialog, import new meters even when no unit column is available, and handle compact dates such as `01062026`. Preview validation and missing-meter discovery run as cancellable background work, with the current result cached for display and import. |
| PDF reports and printing | Implemented | Users can export or print plain PDF reports for the selected meter or all active meters. Reports include meter metadata, statistics, forecast and cost summaries, insufficient-data states, and recent readings. |
| Reading history grouping | Implemented | Meter reading history shows year subheadings so long histories remain scannable without adding duplicate controls. |
| Reading history search | Implemented | The meter reading history has one inline search field that filters readings by note, formatted value, raw value, or formatted date text, with a clear-search affordance and a calm no-results state. |
| Unusual usage surfacing | Implemented | Meter detail flags consumption segments that deviate strongly from the median daily rate (unusually high, unusually low, or decreasing meter values) with plain-language explanations, scoped to the selected statistics range and capped at the three most recent. |
| Mac-native interaction refinement | Implemented | The app now keeps persistent buttons focused on primary creation and modal confirmation, keeps sidebar rows free of duplicated inline actions, moves contextual meter and reading actions into context menus, uses double-click editing for readings, keeps selected-meter export/report/edit/delete available from menu/context paths, documents the main keyboard shortcuts, and adds restrained semantic color for meter kinds, charts, and CSV import preview statuses. Reading edit/delete menu-bar commands remain deferred until there is an explicit selected-reading state. |
| Visual polish | Implemented | The dashboard and meter detail use a shared low-emphasis material surface, accessible meter-kind accents, stronger current-reading hierarchy, compact overview metrics, and scan-friendly reading rows. Advanced tariff, billing, and note fields in the meter form are progressively disclosed while automatically remaining expanded for existing values. |
| GitHub release packaging workflow | Implemented | Published GitHub releases archive the app with Xcode 26.4, ad-hoc sign and verify the archived app bundle, package it as a DMG, and upload the DMG to the release using the DocNest workflow pattern. |
| In-app macOS updates | Implemented | Users can manually check for updates from the About window or Help menu. Meter2 checks the latest GitHub release, requires a DMG asset, downloads and verifies the contained app, replaces the current app with rollback, and relaunches. |
| Reading reminders | Deferred | Reminder support is planned for a later product depth phase. |
| Photo attachments and OCR | Deferred | Richer capture features are out of scope for the MVP. |
| Advanced tariff models | Deferred | Tiered pricing and complex tariff structures are deferred. |

## Virtual Meter Design

### User Experience

- Add one meter-creation flow with a clear `Manual` or `Virtual` type choice. Editing preserves the chosen type; converting an existing manual meter into a virtual meter, or the reverse, is out of scope for the first version because it creates ambiguous reading ownership.
- A virtual meter requires a name and at least one source term. Each term selects an existing meter and a `+` or `−` operation. The first version uses an implicit factor of `1`; arbitrary multiplication factors are deferred until a concrete use case requires them.
- Source meters must use the same unit. The virtual meter inherits that unit and cannot edit it independently. Its display kind defaults to the first source but remains user-selectable for presentation.
- The formula is shown in the form and meter detail header, for example `Solar production − Grid feed-in`.
- Virtual meters cannot accept manual readings and cannot be CSV import targets. Their Add Reading actions are absent rather than disabled.
- Virtual meters participate in the dashboard, sidebar, search, period statistics, charts, anomaly detection, forecasts, CSV export, PDF reports, printing, archive, and delete workflows using their derived series.
- Deleting a virtual meter deletes only its formula. Deleting a source meter is blocked while a virtual meter depends on it, with a localized message naming the dependent virtual meters. Archiving a source is allowed and does not break calculations.

### Persistence Model

- Keep `Meter` as the user-visible entity and add an explicit persisted meter type (`manual` or `virtual`) with a backward-compatible default of `manual` for existing stores.
- Add a `VirtualMeterTerm` SwiftData model containing a stable ID, owning virtual meter, source meter, signed operation, and display order.
- The owning virtual meter cascades deletion to its terms. Source relationships never cascade to source meters. A source meter may be referenced by multiple virtual meters.
- Do not persist generated virtual readings. The formula is the source of truth, so edits, imports, and deletions in source readings are reflected immediately without a synchronization job or stale cache.
- The first version allows only manual meters as sources. This prevents circular dependencies by construction. Virtual-on-virtual formulas may be added later with explicit directed-acyclic-graph validation and cycle diagnostics.

### Calculation Contract

- Treat every source as a cumulative reading series. Normalize date-only and date-time values using the existing reading timestamp rules.
- Build candidate timestamps from the sorted union of all source reading timestamps.
- The valid virtual coverage is the intersection of all source coverage windows. Discard candidate timestamps outside that intersection; never extrapolate before the first or after the last reading of any source.
- At each retained timestamp, use the exact source value when available or the existing linear interpolation rule between surrounding source readings, then calculate the signed sum. For self-consumption, `virtual = total solar production − grid feed-in`.
- Coalesce equivalent timestamps at the app’s displayed precision and generate stable derived reading IDs from the virtual meter ID plus timestamp so sorting and export remain deterministic.
- Preserve negative calculated values because they can reveal an invalid formula, meter reset, or inconsistent source data. Surface a localized warning in the virtual meter detail instead of silently clamping the result.
- A virtual series needs at least two derived points for consumption statistics. When source coverage does not overlap or is insufficient, show the existing calm insufficient-data state plus a virtual-meter-specific explanation.
- Forecast and anomaly logic consume the same derived series as all other statistics. A virtual meter may define its own tariff and billing period; source tariffs are never combined implicitly.

### Domain Boundary

- Use one resolver service for manual and virtual reading series. Generated readings remain transient and are never inserted into SwiftData. SwiftUI views, CSV export, and PDF reports must not duplicate formula evaluation.
- Replace direct analytics/report/export access to `meter.readings` with a single resolved-series boundary. Editing and deletion UI continues to use stored manual readings only.
- Resolve a consistent snapshot before background CSV or PDF work so source edits cannot mix old and new values within one export or report.

### Validation And Error States

- Reject an empty formula, duplicate use of the same source, self-reference, virtual sources in the first version, and mismatched units. A formula without current overlapping source coverage remains valid and shows an insufficient-data state.
- Keep a saved formula valid when a source has temporarily insufficient readings; show insufficient data rather than forcing formula deletion.
- Block source deletion before mutation and list every dependent virtual meter. The block must apply to menu, context-menu, and any future bulk deletion path.
- Persistence failures while creating or editing a formula use the existing save/rollback boundary and keep the form open with all terms intact.

### Implementation Sequence

1. Add the backward-compatible meter type and `VirtualMeterTerm` persistence model, migration coverage, formula validation, and dependency lookup.
2. Introduce the reading-series value boundary and refactor analytics, presentation building, CSV export, and PDF snapshots to consume resolved series without changing manual-meter results.
3. Implement and test the virtual-series resolver, including timestamp union, coverage intersection, interpolation, signed sums, stable IDs, negative results, and insufficient overlap.
4. Extend the meter form and detail header with the manual/virtual workflow and formula presentation; remove manual-reading actions for virtual meters.
5. Integrate dashboard, statistics, charts, forecasts, anomalies, CSV, PDF, printing, archive, and guarded deletion.
6. Perform light/dark visual verification at minimum window size in English and German, then run the full non-UI suite and required lightweight review.

### Required Test Coverage

- Existing stores decode all current meters as manual without data loss.
- Formula persistence round-trips terms, signs, and order; deleting a virtual meter preserves every source meter and reading.
- Source deletion is blocked for one or multiple dependents and succeeds after formulas are removed.
- Exact timestamps and staggered timestamps produce the expected sums and differences through interpolation.
- Coverage uses intersection rather than extrapolation; non-overlapping and single-point sources produce typed insufficient-data results.
- Date-only/date-time combinations coalesce consistently, results are deterministic, negative values remain visible, and unit mismatches are rejected.
- The solar example verifies `production − feed-in = self-consumption` across statistics, chart buckets, CSV rows, and PDF snapshots.
- Manual-meter analytics, import, export, reports, persistence rollback, and reading editing remain unchanged after adopting the resolved-series boundary.
- Virtual meters expose no add/edit/delete reading actions, while their formula edit, archive, export, report, and delete actions remain available and localized in English and German.

## Lessons Learned

| Date | Area | Problem | Solution | Prevention |
| --- | --- | --- | --- | --- |
| 2026-05-07 | Validation | Duplicate readings could bypass checks when timestamps differed by seconds but displayed as the same minute. | Normalize reading timestamps to the displayed minute before validation and saving. | Keep duplicate timestamp tests aligned with UI date precision. |
| 2026-05-07 | Forecasting | Current-period estimates could undercount consumption when the billing period started between two readings. | Interpolate the estimated reading value at the billing-period start. | Cover period-start interpolation in forecast tests. |
| 2026-05-07 | Billing | Disabling custom billing could leave hidden billing periods behind. | Delete custom periods when custom billing is disabled. | Test billing-period cleanup paths when form state changes. |
| 2026-05-07 | Localization | Some German strings used ASCII transliterations or missed new validation keys. | Update the string catalog with proper German text and all introduced keys. | Validate all source catalog keys for English and German values. |
| 2026-05-07 | Testing | Sandboxed Xcode test runs can fail because `testmanagerd` access is restricted. | Run the established test script with the required escalation when sandboxing blocks macOS tests. | Prefer `./scripts/test_meter2.sh` and document sandbox-related failures clearly. |
| 2026-05-07 | Reading entry | New reading forms prefilled `0`, which immediately produced a lower-than-previous warning for existing cumulative meters. | Keep the add-reading value field empty and validate non-blocking warnings only after active value entry focus ends. | Cover blank reading input parsing and keep form validation separate from persisted reading validation. |
| 2026-05-07 | Reading editing | Formatting an existing reading with display precision in the edit field could round the stored raw value when saving without changes. | Use a locale-aware round-tripping value string for edit forms and reject non-finite numeric input. | Test that edit formatting parses back to the original stored value in English and German locales, including long Double values. |
| 2026-05-08 | CSV import | CSV edge cases can hide behind otherwise valid preview flows, including quoted delimiters, duplicate meter names, and duplicate wide headers. | Make delimiter detection quote-aware, keep new-meter keys column-stable, tolerate duplicate existing names, and localize parser errors. | Add unit coverage for parser errors, quoted header delimiters, duplicate existing names, and duplicate wide headers. |
| 2026-05-08 | CSV export | Portable CSV exports can corrupt data through locale-specific decimal parsing or spreadsheet formula interpretation. | Prefer exported dot-decimal values during CSV import, preserve locale-specific grouped values, and protect formula-like text with reversible spreadsheet-safe escaping. | Test German decimal round trips, English grouped values, whitespace-prefixed formulas, and leading-apostrophe formula text. |
| 2026-05-08 | Statistics | Previous-period comparisons can look precise even when the app only has current-period readings and clamps earlier estimates to the first known reading. | Show previous-period comparison only when readings cover the whole comparable previous period. | Cover unavailable previous comparison states in statistics tests. |
| 2026-05-10 | Release workflow | The first Meter2 release workflow used a custom zip build flow that did not match the proven DocNest release packaging workflow. | Align the Meter2 workflow with DocNest by archiving with Xcode 26.4, creating a DMG, and uploading that asset to the release. | Keep release workflow behavior tracked as a requirement and compare future release automation changes against the DocNest pattern. |
| 2026-05-17 | Reading entry | The reading sheet required mouse-heavy date controls and an explicit date/date-time mode even though reading capture should be keyboard-first. | Replace the mode picker with a typed date field that infers time detail, accepts compact dates, supports tab navigation, and lets `+`/`-` step days. The temporary per-meter sidebar plus button was later removed when it duplicated the selected-meter detail action. | Cover compact date parsing and day stepping in unit tests, and keep Add Reading obvious in the selected-meter detail view, context menu, and keyboard shortcut. |
| 2026-05-19 | UX consistency | The keyboard-first reading form and temporary per-meter sidebar add button could look inconsistent with other visible controls when their intent was not explicit. | Keep the typed date field and visible time-detail control. Remove the duplicated sidebar button after the detail, context-menu, and keyboard paths are established. | Cover locale-aware date formatting, manual time-detail overrides, localized action labels, and stale localization cleanup in tests. |
| 2026-05-17 | CSV import | Wide imports with new meters could appear unusable because auto-created meter drafts required units, and German long headers such as `Zählerstand` could confuse meter/value detection. | Allow unit-less imported meter drafts, distinguish meter and value headers before choosing long shape, and parse compact dates in CSV rows. | Cover German long-header detection, unit-less wide imports, and compact CSV dates in unit tests. |
| 2026-05-17 | Forecasting | Statistics cards and forecast cards could show different projected consumption because they used different daily-rate sources. | Use one deterministic projection engine for statistics, forecast cards, and reports; show basis, quality, and recommended next reading. | Cover current-period, recent-reading fallback, stale-reading quality, variable-reading quality, and statistics/forecast consistency in unit tests. |
| 2026-05-19 | Release workflow | GitHub release archives were built with code signing disabled, so the in-app updater rejected the downloaded app with `code object is not signed at all`. | Ad-hoc sign the archived app bundle in the release workflow and verify it with `codesign --verify --deep --strict` before creating the DMG. | Keep a unit test that asserts the release workflow signs and verifies the app before packaging. |
| 2026-06-12 | CSV import | The CSV import sheet could become effectively trapped, with close controls unreliable and app termination blocked while the modal remained open. | Redesign the import dialog with a fixed footer cancel action and scrollable content that cannot push dismissal controls away. | Keep modal import flows with one visible cancel/close control outside scrollable regions and verify dismissal paths during UI changes. |
| 2026-06-19 | CSV import | Preview rows, summary counts, and missing-meter discovery were recomputed synchronously from SwiftUI view properties, which could freeze the dialog for large files. | Build one cached preview payload in a cancellable background task whenever the mapping changes, using value snapshots instead of SwiftData models. | Keep full-file parsing and validation out of view rendering, disable import while a newer preview is pending, and cover payload resolution and cancellation with unit tests. |
| 2026-06-19 | Persistence | SwiftData mutations relied on autosave, so disk or model failures could leave the UI reporting success without durable data. Large imports could also autosave partially while yielding between rows. | Route mutations through an explicit save/rollback boundary, keep failed forms and CSV import mappings open for retry, surface localized errors, and temporarily disable autosave during CSV import batches. | Cover successful saves and rollback-on-failure with unit tests, preserve user input until `ModelContext.save()` succeeds, and never report mutation success before the save completes. |
| 2026-06-19 | First-use workflow | The empty dashboard described the need for a meter without offering a direct creation action, while every sidebar row duplicated Add Reading even though the selected-meter detail view already made it primary. | Add one prominent Add Meter button to the empty dashboard and remove permanent Add Reading buttons from sidebar rows while retaining context-menu and keyboard access. | Keep first-use recovery actions visible and reserve sidebar rows for selection and object context rather than duplicated inline commands. |
| 2026-06-19 | App lifecycle | Closing the main window left Meter2 running without a visible workflow, shown only by the active Dock indicator. A last-window-only policy would still fail while the auxiliary About window remained open, and a `WindowGroup` introduced unnecessary multi-window lifecycle races. | Use one SwiftUI `Window`, mark it explicitly, and terminate when it closes regardless of auxiliary windows; retain the native last-window policy as a fallback. | Cover identifier decisions, real marker attachment, and close-notification routing with focused non-UI AppKit tests. |
