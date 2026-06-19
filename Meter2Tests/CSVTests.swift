import XCTest

@testable import Meter2

final class CSVTests: XCTestCase {
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

    func testCSVDateParserAcceptsCompactDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let compactDate = try XCTUnwrap(CSVDateParser.parse("01062026", calendar: calendar))

        XCTAssertEqual(compactDate.granularity, .dateOnly)
        XCTAssertEqual(calendar.component(.day, from: compactDate.date), 1)
        XCTAssertEqual(calendar.component(.month, from: compactDate.date), 6)
    }

    func testCSVPlannerSuggestedMappingDistinguishesLongMeterAndReadingColumns() throws {
        let document = try CSVParser.parse("Datum,Zähler,Zählerstand,Einheit\n01.06.2026,Strom,42,kWh\n")

        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])

        XCTAssertEqual(mapping.shape, .long)
        XCTAssertEqual(mapping.dateColumnIndex, 0)
        XCTAssertEqual(mapping.meterColumnIndex, 1)
        XCTAssertEqual(mapping.valueColumnIndex, 2)
        XCTAssertEqual(mapping.unitColumnIndex, 3)
    }

    func testCSVPlannerSuggestedMappingTreatsNameAsLongMeterColumn() throws {
        let document = try CSVParser.parse("Date,Name,Value\n2026-06-01,Kitchen,42\n")

        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])

        XCTAssertEqual(mapping.shape, .long)
        XCTAssertEqual(mapping.meterColumnIndex, 1)
        XCTAssertEqual(mapping.valueColumnIndex, 2)
    }

    func testCSVPlannerSuggestedWideMappingCanImportNewMetersWithoutUnits() throws {
        let document = try CSVParser.parse("Datum,Küche,Bad\n01.06.2026,10,20\n")
        let mapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: [])

        let previewRows = CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: [])

        XCTAssertEqual(mapping.shape, .wide)
        XCTAssertEqual(previewRows.map(\.status), [.valid, .valid])
        XCTAssertEqual(CSVImportPlanner.result(from: previewRows).importedReadings, 2)
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

    func testCSVPreviewPayloadResolvesMissingMetersAndCachesSummary() throws {
        let document = try CSVParser.parse(
            "Date,Meter,Value,Unit\n"
                + "2026-05-07,Kitchen,10,\n"
                + "2026-05-08,Kitchen,11,kWh\n"
                + "2026-05-09,Garage,4,m3\n"
        )
        let mapping = CSVColumnMapping(
            shape: .long,
            dateColumnIndex: 0,
            meterColumnIndex: 1,
            valueColumnIndex: 2,
            unitColumnIndex: 3,
            longNewMeterDrafts: [
                "Kitchen": CSVNewMeterDraft(key: "Kitchen", name: "Main meter", unit: "MWh")
            ]
        )

        let payload = try CSVImportPlanner.previewPayload(
            document: document,
            mapping: mapping,
            existingMeters: []
        )

        XCTAssertEqual(payload.missingLongMeterDrafts.map(\.name), ["Garage", "Kitchen"])
        XCTAssertEqual(payload.missingLongMeterDrafts.first { $0.name == "Kitchen" }?.unit, "kWh")
        XCTAssertEqual(payload.mapping.longNewMeterDrafts["Kitchen"]?.name, "Main meter")
        XCTAssertEqual(payload.mapping.longNewMeterDrafts["Kitchen"]?.unit, "MWh")
        XCTAssertEqual(payload.rows.map(\.status), [.valid, .valid, .valid])
        XCTAssertEqual(payload.result, CSVImportResult(
            createdMeters: 2,
            importedReadings: 3,
            skippedDuplicates: 0,
            skippedInvalidRows: 0
        ))
    }

    func testCSVPreviewPayloadHonorsTaskCancellation() async throws {
        let document = try CSVParser.parse("Date,Meter,Value\n2026-05-07,Kitchen,10\n")
        let mapping = CSVColumnMapping(
            shape: .long,
            dateColumnIndex: 0,
            meterColumnIndex: 1,
            valueColumnIndex: 2
        )
        let task = Task.detached {
            await Task.yield()
            return try CSVImportPlanner.previewPayload(
                document: document,
                mapping: mapping,
                existingMeters: []
            )
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected preview generation to stop after cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
