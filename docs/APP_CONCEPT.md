# Meter2 App Concept

## Summary

Meter2 is a native macOS application for manually recording meter readings, turning them into clear consumption insights, and forecasting future usage and costs. The app is designed for households, small offices, landlords, and other users who want a reliable local tool for tracking recurring utility meters without depending on automatic hardware integrations.

The application interface must be available in German and English. Code, developer documentation, and Markdown files are written in English.

## Product Goals

- Make manual meter reading entry fast, calm, and hard to get wrong.
- Visualize consumption trends in a way that is immediately understandable.
- Forecast future consumption, expected costs, and likely next billing totals.
- Support multiple meter types and locations without making the app feel heavy.
- Provide a modern macOS experience that feels native, polished, and trustworthy.
- Keep user data private by default, with local-first storage as the baseline.

## Target Platform

- Platform: macOS.
- UI technology: SwiftUI, using native macOS patterns and system controls.
- Programming language: Swift.
- Minimum supported macOS version: the latest public macOS release at project start.
- Current platform baseline: macOS Tahoe 26.4.1, verified against Apple's public security release list on 2026-05-06.
- Backward compatibility with older macOS versions is not required.

Because older versions do not need to be supported, the app should prefer current Apple APIs and avoid compatibility layers unless they simplify the architecture.

Reference: [Apple security releases](https://support.apple.com/en-us/100100)

## Language And Localization

The user-facing app must support:

- German (`de`)
- English (`en`)

Localization should cover all visible UI strings, empty states, validation messages, chart labels, units, settings, export labels, and forecast explanations.

Recommended default behavior:

- Follow the user's macOS language setting.
- Use locale-aware number, date, currency, and unit formatting.
- Allow per-meter currency and unit configuration where useful.
- Keep internal model names, source code, comments, tests, and Markdown documentation in English.

## Core Use Cases

### Meter Setup

Users can create and manage meters such as:

- Electricity
- Gas
- Water
- Heating
- Solar production
- Custom meter types

Each meter should support:

- Name
- Type
- Location
- Unit
- Decimal precision
- Optional tariff or price per unit
- Optional base fee
- Optional billing period
- Optional notes
- Active or archived state

### Manual Reading Entry

Users can enter a reading with:

- Meter
- Reading value
- Reading date and time
- Optional note
- Optional attachment or photo in a later version

The entry flow should detect common mistakes:

- Reading lower than the previous value for non-resetting meters
- Duplicate readings on the same day
- Large unusual jumps
- Missing or suspicious decimal separators
- Future dates
- Values that conflict with the meter's configured precision

The app should warn clearly without blocking legitimate cases such as meter replacement, rollover, reset, or correction.

### Visualization

The app should provide approachable visual views for:

- Reading history
- Consumption per day, week, month, quarter, and year
- Cost estimates
- Comparison with previous periods
- Rolling average consumption
- Forecasted consumption
- Forecasted billing total
- Outlier readings and unusual usage periods

Charts should be readable at a glance and support native macOS interactions such as hover details, selection, keyboard navigation, and contextual menus.

### Forecasting

Forecasts should explain what they are based on. The first version can use transparent statistical methods rather than opaque machine learning.

Recommended initial forecast methods:

- Average daily consumption over a selected recent period
- Seasonal comparison when enough historical data exists
- Linear projection toward the next billing date
- Cost projection using configured tariffs
- Confidence indicator based on data volume and variability

Forecast output should include:

- Expected consumption by billing date
- Expected cost by billing date
- Change compared with the previous comparable period
- Confidence level
- Plain-language explanation

Example explanation:

> Based on the last 90 days, this meter is expected to consume about 420 kWh by the end of the billing period.

## Information Architecture

Recommended top-level navigation:

- Dashboard
- Meters
- Readings
- Forecasts
- Reports
- Settings

### Dashboard

The dashboard should be the first screen after launch. It should show:

- Active meters
- Latest readings
- Current period consumption
- Forecasted total cost
- Meters needing a new reading
- Notable changes or anomalies

### Meter Detail

Each meter detail view should include:

- Latest reading
- Reading entry action
- Consumption chart
- Forecast card
- Reading table
- Meter settings
- Notes and metadata

### Readings View

The readings view should support:

- Search
- Filtering by meter, date range, type, and location
- Sorting
- Inline correction workflow
- Import and export in later versions

## Data Model

Initial conceptual entities:

### Meter

- `id`
- `name`
- `type`
- `location`
- `unit`
- `decimalPrecision`
- `isActive`
- `createdAt`
- `updatedAt`

### MeterReading

- `id`
- `meterId`
- `value`
- `recordedAt`
- `note`
- `createdAt`
- `updatedAt`
- `source`
- `correctionOfReadingId`

### Tariff

- `id`
- `meterId`
- `currency`
- `unitPrice`
- `baseFee`
- `validFrom`
- `validUntil`

### BillingPeriod

- `id`
- `meterId`
- `startsAt`
- `endsAt`
- `label`

### Forecast

Forecasts can be computed on demand rather than stored permanently in the first version. If stored later, they should include the method, source data range, generated timestamp, and confidence metadata.

## Storage And Privacy

Meter2 should be local-first.

Recommended storage approach:

- SwiftData for structured local data.
- App sandboxing enabled.
- Optional iCloud sync as a future enhancement.
- User-controlled export for portability.
- No analytics or cloud processing by default.

The app handles personal household and cost data, so privacy should be visible in product decisions:

- No account required for the baseline app.
- No network dependency for core functionality.
- Clear export and delete options.
- Transparent storage location and backup behavior.

## User Interface Direction

The interface should feel like a modern native macOS productivity app:

- Calm, data-forward, and spacious enough for charts.
- Native sidebar navigation.
- Toolbar actions for common commands.
- Inspector or detail panels where appropriate.
- Tables for dense reading history.
- Native menus, keyboard shortcuts, context menus, and search.
- Strong empty states that guide the user into creating their first meter or reading.

The visual tone should avoid a marketing-style dashboard. The app should look like a serious utility tool: clear hierarchy, restrained color, excellent typography, and charts that prioritize readability over decoration.

## Accessibility

The app should support:

- VoiceOver labels for charts and key controls.
- Keyboard navigation for all core workflows.
- Dynamic Type where applicable on macOS.
- Sufficient color contrast.
- Non-color-only status indicators.
- Localized accessibility strings.

Charts should provide textual summaries so that trend and forecast information remains accessible.

## Import And Export

MVP import:

- CSV import for readings.
- Wide CSV files with one date column and one value column per meter.
- Long CSV files with date, meter, and value columns.
- Mapping preview before data is written.
- Inline creation of missing meters during import.
- Duplicate rows are skipped while valid rows are still imported.
- Date-only and date-time reading values are supported.

Example wide CSV:

```csv
Date,Kitchen,Bath,Note
2026-05-01,1200.5,340.2,Initial reading
2026-05-15,1242.8,352.9,Mid-month
```

Example long CSV:

```csv
Date,Meter,Value,Note
2026-05-01,Kitchen,1200.5,Initial reading
2026-05-01,Bath,340.2,Initial reading
07.05.2026,Kitchen,1215.0,German date-only input
```

Future import/export:

- CSV export for readings.
- CSV export for meter summaries.
- JSON backup format.
- PDF report export.
- Printable billing-period summary.

## MVP Scope

The first usable version should include:

- Create, edit, archive, and delete meters.
- Add, edit, and delete manual readings.
- Validate reading input against previous readings.
- Show per-meter reading history.
- Show consumption over time.
- Show simple forecast for the current billing period.
- Configure unit, currency, and simple tariff.
- Import readings from mapped CSV files.
- Store and display date-only readings without a time.
- Support German and English UI localization.
- Store all data locally.

## Later Enhancements

Potential future features:

- iCloud sync.
- Reading reminders.
- Photo attachments for readings.
- OCR-assisted reading extraction from photos.
- Multi-user household sharing.
- Advanced tariff models.
- Solar production and self-consumption analysis.
- Budget alerts.
- PDF reports.
- Home screen widgets if the product later expands beyond macOS.
- Smart anomaly detection.

## Non-Goals For The First Version

- Smart meter hardware integration.
- Cloud account system.
- Web app.
- iOS app.
- Complex enterprise reporting.
- Backward compatibility with older macOS versions.
- Fully automated energy optimization recommendations.

## Open Product Questions

- Should Meter2 support only cumulative meters first, or also interval-based meters?
- Should meter replacement be modeled explicitly in MVP?
- Should billing periods be required or optional?
- Should tariffs support tiered pricing in the first version?
- Should the app include reading reminders in MVP or defer them?
- Should exports be per meter, global, or both?

## Success Criteria

Meter2 is successful when a user can:

- Create their first meter in under one minute.
- Add a new reading in a few seconds.
- Understand whether consumption is rising or falling without reading documentation.
- See a believable forecast for the current billing period.
- Trust that their data remains private and under their control.
- Use the app comfortably in German or English.
