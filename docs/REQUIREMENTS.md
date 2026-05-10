# Meter2 Requirements

This file is the shared product requirements record for requested, planned, deferred, rejected, and implemented Meter2 features.

## Feature Requirements

| Feature | Status | Notes |
| --- | --- | --- |
| Native macOS app | Implemented | The app uses a native SwiftUI macOS project. |
| Modern app icon for Light, Dark, and Tinted themes | Implemented | Icon variants are included in the asset catalog. |
| Appearance mode selection | Implemented | Users can choose System, Light, or Dark appearance from one toolbar menu; System follows the current macOS appearance. |
| Bilingual user interface | Implemented | User-facing strings are localized for English and German. |
| Local-first data storage | Implemented | Meter data is stored locally with SwiftData. |
| Manual cumulative meter readings | Implemented | Users can create meters and enter timestamped readings manually. |
| Meter management | Implemented | Users can create, edit, archive, and delete meters. |
| Reading management | Implemented | Users can create, edit, and delete manual readings. |
| Date-only readings | Implemented | Readings can store either a date-only value or a date-time value and display date-only readings without a time. |
| Reading validation | Implemented | Negative values and duplicate timestamps are blocked; lower readings, future dates, and unusually large jumps produce warnings. |
| Reading entry input state | Implemented | New reading forms start with an empty value field, and non-blocking warnings are hidden while the value is actively being typed. |
| Dashboard | Implemented | The dashboard summarizes latest readings, reading counts, average daily consumption, and current estimates. |
| Meter detail view | Implemented | Meter detail includes insights, charts, forecasts, and reading history. |
| Period-based statistics | Implemented | Meter detail statistics can be scoped to month, quarter, year, or all history and show consumption, daily average, projection, cost, and previous-period comparison when comparable data exists. |
| Consumption charts | Implemented | Reading-value and consumption-delta charts are available through Swift Charts. |
| Forecasting | Implemented | Forecasts use average daily consumption between historical readings and support insufficient-data states. |
| Simple tariff and billing support | Implemented | Optional flat unit price, base fee, currency code, and billing periods are supported. |
| CSV export | Implemented | Users can export all readings or the selected meter's readings as reimport-friendly long CSV files. |
| CSV import | Implemented | Users can import wide or long CSV files through a mapping preview, skip duplicates, import valid rows, and create missing meters in the import dialog. |
| GitHub release packaging workflow | Implemented | Published GitHub releases archive the app with Xcode 26.4, package it as a DMG, and upload the DMG to the release using the DocNest workflow pattern. |
| Reading reminders | Deferred | Reminder support is planned for a later product depth phase. |
| iCloud sync | Deferred | Sync is out of scope for the local-first MVP. |
| Photo attachments, OCR, and PDF reports | Deferred | These richer capture and reporting features are out of scope for the MVP. |
| Advanced tariff models | Deferred | Tiered pricing and complex tariff structures are deferred. |

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
