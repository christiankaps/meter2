import SwiftData
import XCTest
@testable import Meter2

final class Meter2Tests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testAppConfigurationMatchesTheProjectSetup() {
        XCTAssertEqual(AppConfiguration.appName, "Meter2")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "de.christiankaps.meter2")
        XCTAssertEqual(AppConfiguration.defaultWindowWidth, 800)
        XCTAssertEqual(AppConfiguration.defaultWindowHeight, 520)
    }

    func testAppBundleIsLoadedWithTheExpectedIconConfiguration() {
        let appBundle = Bundle.allBundles.first { $0.bundleIdentifier == AppConfiguration.bundleIdentifier }

        XCTAssertNotNil(appBundle)
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Meter2")
        XCTAssertEqual(appBundle?.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIconVariants")
    }

    func testAppearanceModeMapsToExpectedColorSchemes() {
        XCTAssertNil(AppearanceMode.system.preferredColorScheme)
        XCTAssertEqual(AppearanceMode.light.preferredColorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testAppearanceModeFallsBackToSystemForUnknownStoredValue() {
        XCTAssertEqual(AppearanceMode.mode(for: "unexpected"), .system)
        XCTAssertEqual(AppearanceMode.mode(for: AppearanceMode.dark.rawValue), .dark)
    }

    func testReadingValidationBlocksNegativeValues() {
        let result = MeterAnalytics.validateReading(
            value: -1,
            recordedAt: Date(),
            existingReadings: []
        )

        XCTAssertEqual(result.blockingIssues, [.negativeValue])
        XCTAssertFalse(result.canSave)
    }

    func testReadingValidationBlocksExactDuplicateTimestamp() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 100)
        let existing = MeterReading(value: 10, recordedAt: timestamp)

        let result = MeterAnalytics.validateReading(
            value: 11,
            recordedAt: timestamp,
            existingReadings: [existing]
        )

        XCTAssertEqual(result.blockingIssues, [.duplicateTimestamp])
        XCTAssertFalse(result.canSave)
    }

    func testReadingValidationBlocksDuplicatesWithinDisplayedMinute() {
        let first = Date(timeIntervalSinceReferenceDate: 120.1)
        let second = Date(timeIntervalSinceReferenceDate: 145.9)
        let existing = MeterReading(value: 10, recordedAt: first)

        let result = MeterAnalytics.validateReading(
            value: 11,
            recordedAt: second,
            existingReadings: [existing]
        )

        XCTAssertEqual(result.blockingIssues, [.duplicateTimestamp])
        XCTAssertFalse(result.canSave)
    }

    func testReadingValidationBlocksDateOnlyDuplicatesOnSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let existingDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 14, minute: 30))!
        let importDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let existing = MeterReading(value: 10, recordedAt: existingDate, recordedAtGranularity: .dateTime)

        let result = MeterAnalytics.validateReading(
            value: 11,
            recordedAt: importDate,
            granularity: .dateOnly,
            existingReadings: [existing]
        )

        XCTAssertEqual(result.blockingIssues, [.duplicateTimestamp])
        XCTAssertFalse(result.canSave)
    }

    func testReadingDateOnlyValuesNormalizeToStartOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 14, minute: 30))!
        let normalized = MeterAnalytics.normalizedForStorage(date, granularity: .dateOnly, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!

        XCTAssertEqual(normalized, expected)
    }

    func testMeterReadingDefaultsToDateTimeGranularity() {
        let reading = MeterReading(value: 10, recordedAt: Date())

        XCTAssertEqual(reading.recordedAtGranularity, .dateTime)
    }

    func testReadingValidationWarnsWhenLowerThanPrevious() {
        let first = MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 100))
        let result = MeterAnalytics.validateReading(
            value: 90,
            recordedAt: Date(timeIntervalSinceReferenceDate: 200),
            existingReadings: [first]
        )

        XCTAssertEqual(result.warnings, [.lowerThanPrevious])
        XCTAssertTrue(result.canSave)
    }

    func testReadingValueParserTreatsBlankInputAsIncomplete() {
        XCTAssertNil(ReadingValueParser.parse(""))
        XCTAssertNil(ReadingValueParser.parse("   "))
    }

    func testReadingValueParserRejectsNonFiniteInput() {
        XCTAssertNil(ReadingValueParser.parse("NaN", locale: Locale(identifier: "en_US")))
        XCTAssertNil(ReadingValueParser.parse("inf", locale: Locale(identifier: "en_US")))
        XCTAssertNil(ReadingValueParser.parse("infinity", locale: Locale(identifier: "en_US")))
        XCTAssertNil(ReadingValueParser.parse("-infinity", locale: Locale(identifier: "en_US")))
    }

    func testReadingValueParserAcceptsLocalizedDecimalValues() throws {
        let germanValue = try XCTUnwrap(ReadingValueParser.parse("12,5", locale: Locale(identifier: "de_DE")))
        let englishValue = try XCTUnwrap(ReadingValueParser.parse("12.5", locale: Locale(identifier: "en_US")))

        XCTAssertEqual(germanValue, 12.5, accuracy: 0.001)
        XCTAssertEqual(englishValue, 12.5, accuracy: 0.001)
    }

    func testReadingValueParserFormatForEditingPreservesStoredPrecision() throws {
        let originalValue = 12.3456789
        let text = ReadingValueParser.formatForEditing(originalValue, locale: Locale(identifier: "en_US"))
        let parsedValue = try XCTUnwrap(ReadingValueParser.parse(text, locale: Locale(identifier: "en_US")))

        XCTAssertEqual(parsedValue, originalValue, accuracy: 0.000_000_001)
    }

    func testReadingValueParserFormatForEditingRoundTripsInGermanLocale() throws {
        let originalValue = 1.234
        let locale = Locale(identifier: "de_DE")
        let text = ReadingValueParser.formatForEditing(originalValue, locale: locale)
        let parsedValue = try XCTUnwrap(ReadingValueParser.parse(text, locale: locale))

        XCTAssertEqual(text, "1,234")
        XCTAssertEqual(parsedValue, originalValue, accuracy: 0.000_000_001)
    }

    func testReadingValueParserFormatForEditingRoundTripsLongDoubleValue() throws {
        let originalValue = 0.12345678901234566
        let locale = Locale(identifier: "de_DE")
        let text = ReadingValueParser.formatForEditing(originalValue, locale: locale)
        let parsedValue = try XCTUnwrap(ReadingValueParser.parse(text, locale: locale))

        XCTAssertEqual(text, "0,12345678901234566")
        XCTAssertEqual(parsedValue, originalValue, accuracy: 0)
    }

    func testCSVParserParsesCommaSemicolonTabAndQuotedFields() throws {
        let comma = try CSVParser.parse("Date,Kitchen\n2026-05-07,10\n")
        XCTAssertEqual(comma.delimiter, ",")
        XCTAssertEqual(comma.headers, ["Date", "Kitchen"])
        XCTAssertEqual(comma.rows, [["2026-05-07", "10"]])

        let semicolon = try CSVParser.parse("Date;Kitchen\n2026-05-07;10\n")
        XCTAssertEqual(semicolon.delimiter, ";")

        let tab = try CSVParser.parse("Date\tKitchen\n2026-05-07\t10\n")
        XCTAssertEqual(tab.delimiter, "\t")

        let quoted = try CSVParser.parse("Date,Note,Kitchen\n2026-05-07,\"A \"\"quoted\"\" note\",10\n")
        XCTAssertEqual(quoted.rows.first?[1], #"A "quoted" note"#)
    }

    func testCSVParserDetectsDelimiterWithoutCountingQuotedHeaderSeparators() throws {
        let document = try CSVParser.parse("\"Date, imported\";Kitchen\n2026-05-07;10\n")

        XCTAssertEqual(document.delimiter, ";")
        XCTAssertEqual(document.headers, ["Date, imported", "Kitchen"])
        XCTAssertEqual(document.rows, [["2026-05-07", "10"]])
    }

    func testCSVParserErrorsExposeLocalizedDescriptions() {
        XCTAssertEqual(CSVParserError.emptyDocument.localizedDescription, String(localized: "csv.importError.emptyDocument"))
        XCTAssertEqual(CSVParserError.missingHeaders.localizedDescription, String(localized: "csv.importError.missingHeaders"))
        XCTAssertEqual(CSVParserError.unclosedQuote.localizedDescription, String(localized: "csv.importError.unclosedQuote"))
    }

    func testCSVExporterCreatesHeaderOnlyExportForNoReadings() {
        let csv = CSVExporter.export(meters: [], scope: .allReadings)

        XCTAssertEqual(csv, "Date,Meter,Value,Unit,Note\n")
    }

    func testCSVExporterEscapesSpecialFieldsAndBlankNotes() throws {
        let meter = Meter(name: #"Kitchen, "Main""#, kind: .custom, unit: "kWh")
        let reading = MeterReading(
            value: 12.5,
            recordedAt: Date(timeIntervalSinceReferenceDate: 0),
            note: "Line 1\nLine 2",
            meter: meter
        )
        meter.readings.append(reading)

        let csv = CSVExporter.export(meters: [meter], scope: .allReadings, calendar: utcCalendar())

        XCTAssertEqual(csv, "Date,Meter,Value,Unit,Note\n2001-01-01 00:00,\"Kitchen, \"\"Main\"\"\",12.5,kWh,\"Line 1\nLine 2\"\n")
    }

    func testCSVExporterFormatsDateOnlyWithoutTimeAndDateTimeWithMinutePrecision() throws {
        let calendar = utcCalendar()
        let meter = Meter(name: "Kitchen", kind: .custom, unit: "kWh")
        let dateOnly = MeterReading(
            value: 10,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!,
            recordedAtGranularity: .dateOnly,
            meter: meter
        )
        let dateTime = MeterReading(
            value: 11,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 14, minute: 30, second: 45))!,
            recordedAtGranularity: .dateTime,
            meter: meter
        )
        meter.readings.append(contentsOf: [dateTime, dateOnly])

        let csv = CSVExporter.export(meters: [meter], scope: .allReadings, calendar: calendar)

        XCTAssertEqual(csv, """
        Date,Meter,Value,Unit,Note
        2026-05-07,Kitchen,10.0,kWh,
        2026-05-08 14:30,Kitchen,11.0,kWh,

        """)
    }

    func testCSVExporterCanExportOneSelectedMeterOrAllMetersInStableOrder() {
        let calendar = utcCalendar()
        let kitchen = Meter(name: "Kitchen", kind: .custom, unit: "kWh")
        let bath = Meter(name: "Bath", kind: .custom, unit: "m3")
        kitchen.readings.append(MeterReading(value: 20, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!, recordedAtGranularity: .dateOnly, meter: kitchen))
        bath.readings.append(MeterReading(value: 5, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!, recordedAtGranularity: .dateOnly, meter: bath))
        kitchen.readings.append(MeterReading(value: 10, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!, recordedAtGranularity: .dateOnly, meter: kitchen))

        let allCSV = CSVExporter.export(meters: [kitchen, bath], scope: .allReadings, calendar: calendar)
        let kitchenCSV = CSVExporter.export(meters: [kitchen, bath], scope: .meter(kitchen.id), calendar: calendar)

        XCTAssertEqual(allCSV, """
        Date,Meter,Value,Unit,Note
        2026-05-07,Bath,5.0,m3,
        2026-05-07,Kitchen,10.0,kWh,
        2026-05-08,Kitchen,20.0,kWh,

        """)
        XCTAssertEqual(kitchenCSV, """
        Date,Meter,Value,Unit,Note
        2026-05-07,Kitchen,10.0,kWh,
        2026-05-08,Kitchen,20.0,kWh,

        """)
    }

    func testCSVExporterSuggestsSafeFileNames() {
        let meter = Meter(name: "Kitchen/Main", kind: .custom, unit: "kWh")

        XCTAssertEqual(CSVExporter.suggestedFileName(for: .allReadings, meters: [meter]), "meter2-readings.csv")
        XCTAssertEqual(CSVExporter.suggestedFileName(for: .meter(meter.id), meters: [meter]), "meter2-Kitchen-Main-readings.csv")
    }

    func testCSVNumberParserPrefersDotDecimalRoundTripsInGermanLocale() throws {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("0.001", locale: locale)), 0.001, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("1.234", locale: locale)), 1.234, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("12.345", locale: locale)), 12.345, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("1,234", locale: locale)), 1.234, accuracy: 0.000_001)
    }

    func testCSVNumberParserKeepsEnglishGroupedValuesAsThousands() throws {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("1,234", locale: locale)), 1234, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(CSVNumberParser.parse("12,345", locale: locale)), 12_345, accuracy: 0.000_001)
    }

    func testCSVExporterProtectsFormulaLikeTextAndImportRestoresIt() throws {
        XCTAssertEqual(CSVSpreadsheetSafety.restoredText(CSVExporter.spreadsheetSafeText(" \t=hidden")), " \t=hidden")

        let calendar = utcCalendar()
        let meter = Meter(name: " \t=Kitchen", kind: .custom, unit: "\t@kWh")
        let reading = MeterReading(
            value: 10,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!,
            recordedAtGranularity: .dateOnly,
            note: "-manual",
            meter: meter
        )
        meter.readings.append(reading)

        let csv = CSVExporter.export(meters: [meter], scope: .allReadings, calendar: calendar)
        let document = try CSVParser.parse(csv)
        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])
        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [], calendar: calendar)
        let plannedReading = try XCTUnwrap(previewRows.first?.plannedReading)

        XCTAssertEqual(csv, "Date,Meter,Value,Unit,Note\n2026-05-07,' \t=Kitchen,10.0,'\t@kWh,'-manual\n")
        XCTAssertEqual(previewRows.first?.meterName, " \t=Kitchen")
        XCTAssertEqual(plannedReading.note, "-manual")
        XCTAssertEqual(CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows).first?.unit, "\t@kWh")
    }

    func testCSVExporterPreservesLegitimateLeadingApostropheBeforeFormulaCharacters() throws {
        for original in ["''=Kitchen", "''+Kitchen", "''-Kitchen", "''@Kitchen"] {
            XCTAssertEqual(CSVSpreadsheetSafety.restoredText(CSVExporter.spreadsheetSafeText(original)), original)
        }

        let calendar = utcCalendar()
        let meter = Meter(name: "''=Kitchen", kind: .custom, unit: "''@kWh")
        let reading = MeterReading(
            value: 10,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!,
            recordedAtGranularity: .dateOnly,
            note: "''-manual",
            meter: meter
        )
        meter.readings.append(reading)

        let csv = CSVExporter.export(meters: [meter], scope: .allReadings, calendar: calendar)
        let document = try CSVParser.parse(csv)
        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])
        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [], calendar: calendar)
        let plannedReading = try XCTUnwrap(previewRows.first?.plannedReading)

        XCTAssertEqual(csv, "Date,Meter,Value,Unit,Note\n2026-05-07,'''=Kitchen,10.0,'''@kWh,'''-manual\n")
        XCTAssertEqual(previewRows.first?.meterName, "''=Kitchen")
        XCTAssertEqual(plannedReading.note, "''-manual")
        XCTAssertEqual(CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows).first?.unit, "''@kWh")
    }

    func testCSVExportedRowsCanPrefillUnitsWhenReimported() throws {
        let document = try CSVParser.parse("Date,Meter,Value,Unit,Note\n2026-05-07,Kitchen,10.0,kWh,Start\n")
        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])
        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])

        XCTAssertEqual(mapping.unitColumnIndex, 3)
        XCTAssertEqual(previewRows.first?.status, .valid)
        XCTAssertEqual(CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows).first?.unit, "kWh")
    }

    func testCSVDateParserDetectsDateOnlyAndDateTimeFormats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let isoDate = try XCTUnwrap(CSVDateParser.parse("2026-05-07", calendar: calendar))
        let germanDate = try XCTUnwrap(CSVDateParser.parse("07.05.2026", calendar: calendar))
        let usDateTime = try XCTUnwrap(CSVDateParser.parse("05/07/2026 14:30", calendar: calendar))

        XCTAssertEqual(isoDate.granularity, .dateOnly)
        XCTAssertEqual(germanDate.granularity, .dateOnly)
        XCTAssertEqual(usDateTime.granularity, .dateTime)
    }

    func testCSVPlannerImportsWideRowsAndCreatesMeters() throws {
        let document = try CSVParser.parse("Date,Kitchen,Bath\n2026-05-07,10,20\n")
        let mapping = CSVColumnMapping(
            shape: .wide,
            dateColumnIndex: 0,
            wideValueMappings: [
                CSVWideValueMapping(columnIndex: 1, target: .new(CSVNewMeterDraft(key: "Kitchen", name: "Kitchen", unit: "kWh"))),
                CSVWideValueMapping(columnIndex: 2, target: .new(CSVNewMeterDraft(key: "Bath", name: "Bath", unit: "m3")))
            ]
        )

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])
        let result = CSVImportPlanner.result(from: previewRows)

        XCTAssertEqual(previewRows.map(\.status), [.valid, .valid])
        XCTAssertEqual(result.createdMeters, 2)
        XCTAssertEqual(result.importedReadings, 2)
        XCTAssertEqual(previewRows.compactMap(\.plannedReading).map(\.granularity), [.dateOnly, .dateOnly])
    }

    func testCSVPlannerSuggestedMappingToleratesDuplicateExistingMeterNames() throws {
        let kitchen = Meter(name: "Kitchen", kind: .custom, unit: "kWh")
        let duplicateKitchen = Meter(name: "kitchen", kind: .custom, unit: "m3")
        let document = try CSVParser.parse("Date,Kitchen\n2026-05-07,10\n")

        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [kitchen, duplicateKitchen])

        guard case .existing(let mappedID) = mapping.wideValueMappings.first?.target else {
            return XCTFail("Expected duplicate meter names to map to an existing meter without crashing.")
        }
        XCTAssertEqual(mappedID, kitchen.id)
    }

    func testCSVPlannerKeepsDuplicateWideHeadersAsSeparateNewMeterDrafts() throws {
        let document = try CSVParser.parse("Date,Kitchen,Kitchen\n2026-05-07,10,20\n")
        var mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])
        mapping.wideValueMappings = mapping.wideValueMappings.map { valueMapping in
            guard case .new(var draft) = valueMapping.target else { return valueMapping }
            draft.unit = "kWh"
            return CSVWideValueMapping(columnIndex: valueMapping.columnIndex, target: .new(draft))
        }

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])
        let drafts = CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows)

        XCTAssertEqual(previewRows.map(\.status), [.valid, .valid])
        XCTAssertEqual(Set(drafts.map(\.key)).count, 2)
        XCTAssertEqual(drafts.count, 2)
    }

    func testCSVPlannerImportsLongRowsAndCreatesMissingMeters() throws {
        let document = try CSVParser.parse("Date,Meter,Value,Note\n2026-05-07,Kitchen,10,Start\n")
        let mapping = CSVColumnMapping(
            shape: .long,
            dateColumnIndex: 0,
            noteColumnIndex: 3,
            meterColumnIndex: 1,
            valueColumnIndex: 2,
            longCreateMissingMeters: true,
            longNewMeterDrafts: ["Kitchen": CSVNewMeterDraft(key: "Kitchen", name: "Kitchen", unit: "kWh")]
        )

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])
        let plannedReading = try XCTUnwrap(previewRows.first?.plannedReading)

        XCTAssertEqual(previewRows.first?.status, .valid)
        XCTAssertEqual(previewRows.first?.meterName, "Kitchen")
        XCTAssertEqual(plannedReading.note, "Start")
        XCTAssertEqual(CSVImportPlanner.result(from: previewRows).createdMeters, 1)
    }

    func testCSVPlannerSkipsDuplicatesAndInvalidRowsWhileKeepingValidRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let existingDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let meter = Meter(name: "Kitchen", kind: .custom, unit: "kWh")
        meter.readings.append(MeterReading(value: 9, recordedAt: existingDate, recordedAtGranularity: .dateOnly, meter: meter))
        let document = try CSVParser.parse("Date,Meter,Value\n2026-05-07,Kitchen,10\n2026-05-08,Kitchen,bad\n2026-05-09,Kitchen,12\n")
        let mapping = CSVColumnMapping(
            shape: .long,
            dateColumnIndex: 0,
            meterColumnIndex: 1,
            valueColumnIndex: 2
        )

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [meter], calendar: calendar)
        let result = CSVImportPlanner.result(from: previewRows)

        XCTAssertEqual(previewRows.map(\.status), [.duplicate, .invalid, .valid])
        XCTAssertEqual(result.importedReadings, 1)
        XCTAssertEqual(result.skippedDuplicates, 1)
        XCTAssertEqual(result.skippedInvalidRows, 1)
    }

    func testCSVPlannerDetectsDateOnlyAndDateTimeDuplicatesWithinImport() throws {
        let document = try CSVParser.parse("Date,Meter,Value\n2026-05-07,Kitchen,10\n2026-05-07 14:30,Kitchen,11\n")
        let mapping = CSVColumnMapping(
            shape: .long,
            dateColumnIndex: 0,
            meterColumnIndex: 1,
            valueColumnIndex: 2,
            longNewMeterDrafts: ["Kitchen": CSVNewMeterDraft(key: "Kitchen", name: "Kitchen", unit: "kWh")]
        )

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])

        XCTAssertEqual(previewRows.map(\.status), [.valid, .duplicate])
    }

    func testCSVPlannerRejectsMissingRequiredLongMapping() throws {
        let document = try CSVParser.parse("Date,Meter,Value\n2026-05-07,Kitchen,10\n")
        let mapping = CSVColumnMapping(shape: .long, dateColumnIndex: 0)

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])

        XCTAssertEqual(previewRows.first?.status, .invalid)
    }

    func testReadingValidationWarnsWhenBackdatedValueIsHigherThanNext() {
        let next = MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 300))
        let result = MeterAnalytics.validateReading(
            value: 120,
            recordedAt: Date(timeIntervalSinceReferenceDate: 200),
            existingReadings: [next]
        )

        XCTAssertEqual(result.warnings, [.higherThanNext])
        XCTAssertTrue(result.canSave)
    }

    func testReadingValidationWarnsForFutureDates() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let result = MeterAnalytics.validateReading(
            value: 1,
            recordedAt: Date(timeIntervalSinceReferenceDate: 200),
            existingReadings: [],
            now: now
        )

        XCTAssertEqual(result.warnings, [.futureDate])
        XCTAssertTrue(result.canSave)
    }

    func testReadingValidationWarnsForUnusualJump() {
        let first = MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0))
        let second = MeterReading(value: 110, recordedAt: Date(timeIntervalSinceReferenceDate: 86_400))
        let third = MeterReading(value: 120, recordedAt: Date(timeIntervalSinceReferenceDate: 172_800))

        let result = MeterAnalytics.validateReading(
            value: 300,
            recordedAt: Date(timeIntervalSinceReferenceDate: 259_200),
            existingReadings: [first, second, third]
        )

        XCTAssertTrue(result.warnings.contains(.unusualJump))
        XCTAssertTrue(result.canSave)
    }

    func testReadingsAreSortedAscendingAndDescending() {
        let first = MeterReading(value: 1, recordedAt: Date(timeIntervalSinceReferenceDate: 100))
        let second = MeterReading(value: 2, recordedAt: Date(timeIntervalSinceReferenceDate: 200))
        let third = MeterReading(value: 3, recordedAt: Date(timeIntervalSinceReferenceDate: 300))
        let shuffled = [second, third, first]

        XCTAssertEqual(MeterAnalytics.sortedReadingsAscending(shuffled).map(\.value), [1, 2, 3])
        XCTAssertEqual(MeterAnalytics.sortedReadingsDescending(shuffled).map(\.value), [3, 2, 1])
    }

    func testConsumptionDeltasAreCalculatedBetweenReadings() {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 125, recordedAt: Date(timeIntervalSinceReferenceDate: 86_400)),
            MeterReading(value: 140, recordedAt: Date(timeIntervalSinceReferenceDate: 172_800))
        ]

        let deltas = MeterAnalytics.consumptionDeltas(from: readings)

        XCTAssertEqual(deltas.map(\.value), [25, 15])
    }

    func testAverageDailyConsumptionUsesFullHistory() throws {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 130, recordedAt: Date(timeIntervalSinceReferenceDate: 3 * 86_400))
        ]

        XCTAssertEqual(try XCTUnwrap(MeterAnalytics.averageDailyConsumption(from: readings)), 10, accuracy: 0.001)
    }

    func testForecastRequiresAtLeastTwoReadings() {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0))
        ]

        let result = MeterAnalytics.forecast(
            readings: readings,
            periodStart: Date(timeIntervalSinceReferenceDate: 0),
            periodEnd: Date(timeIntervalSinceReferenceDate: 86_400)
        )

        XCTAssertNil(result)
    }

    func testForecastProjectsConsumptionAndCost() throws {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 130, recordedAt: Date(timeIntervalSinceReferenceDate: 3 * 86_400))
        ]
        let tariff = MeterTariff(currencyCode: "EUR", unitPrice: 0.5, baseFee: 2)

        let result = MeterAnalytics.forecast(
            readings: readings,
            periodStart: Date(timeIntervalSinceReferenceDate: 0),
            periodEnd: Date(timeIntervalSinceReferenceDate: 5 * 86_400),
            tariff: tariff
        )

        let forecast = try XCTUnwrap(result)
        XCTAssertEqual(forecast.averageDailyConsumption, 10, accuracy: 0.001)
        XCTAssertEqual(forecast.projectedConsumption, 50, accuracy: 0.001)
        XCTAssertEqual(forecast.projectedValue, 150, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(forecast.projectedCost), 27, accuracy: 0.001)
    }

    func testForecastIncludesConsumptionAlreadyUsedInBillingPeriod() throws {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 130, recordedAt: Date(timeIntervalSinceReferenceDate: 3 * 86_400)),
            MeterReading(value: 140, recordedAt: Date(timeIntervalSinceReferenceDate: 4 * 86_400))
        ]

        let result = MeterAnalytics.forecast(
            readings: readings,
            periodStart: Date(timeIntervalSinceReferenceDate: 2 * 86_400),
            periodEnd: Date(timeIntervalSinceReferenceDate: 5 * 86_400)
        )

        XCTAssertEqual(try XCTUnwrap(result).projectedConsumption, 30, accuracy: 0.001)
    }

    func testEstimatedValueInterpolatesBetweenReadings() throws {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 130, recordedAt: Date(timeIntervalSinceReferenceDate: 3 * 86_400))
        ]

        let value = try XCTUnwrap(
            MeterAnalytics.estimatedValue(
                at: Date(timeIntervalSinceReferenceDate: 2 * 86_400),
                readings: readings
            )
        )

        XCTAssertEqual(value, 120, accuracy: 0.001)
    }

    func testDateNormalizationUsesDisplayedMinutePrecision() {
        let date = Date(timeIntervalSinceReferenceDate: 125.75)
        let normalized = MeterAnalytics.normalizedToDisplayedMinute(date, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(normalized.timeIntervalSinceReferenceDate, 120, accuracy: 0.001)
    }

    func testSwiftDataPersistsMeterReadingArchiveAndCascadeDelete() throws {
        let schema = Schema([Meter.self, MeterReading.self, MeterTariff.self, BillingPeriod.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let meter = Meter(name: "Main", kind: .electricity)
        context.insert(meter)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(), meter: meter))
        try context.save()

        var meterFetch = FetchDescriptor<Meter>()
        meterFetch.includePendingChanges = true
        XCTAssertEqual(try context.fetch(meterFetch).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeterReading>()).count, 1)

        meter.isArchived = true
        try context.save()
        XCTAssertTrue(try XCTUnwrap(context.fetch(meterFetch).first).isArchived)

        context.delete(meter)
        try context.save()
        XCTAssertEqual(try context.fetch(meterFetch).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeterReading>()).count, 0)
    }

    func testLocalizationCatalogContainsEnglishAndGermanEntries() throws {
        let appBundle = try XCTUnwrap(
            Bundle.allBundles.first { $0.bundleIdentifier == AppConfiguration.bundleIdentifier }
        )
        XCTAssertNotNil(appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        XCTAssertNotNil(appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "de"))

        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])

        for key in strings.keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "de"] {
                let localization = try XCTUnwrap(
                    localizations[locale] as? [String: Any],
                    "Missing \(locale) localization for \(key)"
                )
                let stringUnit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "Missing \(locale) string unit for \(key)"
                )
                XCTAssertEqual(
                    stringUnit["state"] as? String,
                    "translated",
                    "Unexpected \(locale) localization state for \(key)"
                )
                let value = try XCTUnwrap(
                    stringUnit["value"] as? String,
                    "Missing \(locale) localized value for \(key)"
                )
                XCTAssertFalse(value.isEmpty, "Empty \(locale) localized value for \(key)")
            }
        }
    }
}
