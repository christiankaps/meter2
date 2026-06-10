# Meter2 Improvement Plan

Plan created 2026-06-10 from a comparison of `docs/APP_CONCEPT.md`, `docs/UI_CONCEPT.md`, `docs/REQUIREMENTS.md`, and the current implementation. Work items should be executed directly on `main` following `AGENTS.md`.

## Current State Assessment

The macOS MVP scope is essentially complete: meter and reading management, validation, statistics with advanced time scoping, deterministic forecasting, tariffs and billing periods, CSV import/export, PDF reports, localization, in-app updates, and a GitHub release pipeline are all implemented and covered by roughly 110 unit tests.

The main gaps are:

1. **In-progress committed scope is unfinished.** iCloud sync, the iPhone companion, and shared household collaboration are all marked `In Progress`. The CloudKit sync foundation (`MeterLibrarySync.swift`) and companion views exist, but runtime CloudKit behavior is unverified because it requires a signed developer build (lesson 2026-05-13).
2. **`ContentView.swift` is a 2,800-line monolith.** All macOS UI lives in one file, which makes reviews slower, increases merge risk, and conflicts with the UI concept's recommendation to use view models or services for complex workflows.
3. **Concept features without requirements entries.** The app concept describes a readings view with search, filtering, and sorting, plus outlier/anomaly surfacing; neither is implemented or tracked in `REQUIREMENTS.md`.
4. **Open product questions are still open.** Six questions in `APP_CONCEPT.md` (interval meters, meter replacement modeling, tiered tariffs, reminders in MVP, export scope) have de-facto answers in the shipped app but were never recorded as decisions.

## Phase 1 — Maintainability Foundation

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

## Phase 3 — Close Concept Gaps On macOS

Goal: deliver the concept-described capabilities that the MVP skipped, in order of daily-use value.

- Readings search and filtering: add search plus filtering by meter and date range to the reading history (concept also lists type/location filters; include them only if they stay calm and simple).
- Outlier and anomaly surfacing: flag unusual readings or usage periods in meter detail using the existing deterministic statistics, with a plain-language explanation.
- Accessibility audit: VoiceOver labels for charts and icon-only controls, textual chart summaries, keyboard-only completion of core workflows. Fix gaps found.
- Help coverage: ensure the in-app help documents exactly the shortcuts that are implemented (`UI_CONCEPT.md` shortcut table as the reference).
- Add each delivered item to `REQUIREMENTS.md` with status.

## Phase 4 — Product Depth (Currently Deferred)

Goal: revisit deferred features once Phases 2–3 land. Re-evaluate priority then; do not start these earlier.

- Reading reminders (likely first: high recurring value, low complexity).
- Advanced tariff models (tiered pricing).
- Photo attachments and OCR-assisted capture.
- JSON backup format.

## Housekeeping

- Record answers to the open product questions in `APP_CONCEPT.md` as explicit decisions (e.g., cumulative meters only, billing periods optional, exports both per-meter and global) and remove the questions that are settled.
- Keep `REQUIREMENTS.md` and the Lessons Learned table updated as each phase lands, per `AGENTS.md`.
