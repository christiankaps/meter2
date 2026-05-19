import AppKit
import SwiftData
import XCTest
@testable import Meter2

private final class InMemoryMeterLibrarySyncStateStore: MeterLibrarySyncStateStore {
    private var state: MeterLibrarySyncState?

    func loadState() -> MeterLibrarySyncState? {
        state
    }

    func saveState(_ state: MeterLibrarySyncState) {
        self.state = state
    }
}

final class Meter2Tests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testAppConfigurationMatchesTheProjectSetup() {
        XCTAssertEqual(AppConfiguration.appName, "Meter2")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "de.christiankaps.meter2")
        XCTAssertEqual(AppConfiguration.companionBundleIdentifier, "de.christiankaps.meter2.companion")
        XCTAssertEqual(AppConfiguration.iCloudContainerIdentifier, "iCloud.de.christiankaps.meter2")
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

    @MainActor
    func testSyncEnableQueuesWholeLibraryForOptInMigration() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        let reading = MeterReading(value: 42, recordedAt: Date(timeIntervalSinceReferenceDate: 100), meter: meter)
        let tariff = MeterTariff(currencyCode: "EUR", unitPrice: 0.3, baseFee: 4, meter: meter)
        let period = BillingPeriod(
            startsAt: Date(timeIntervalSinceReferenceDate: 0),
            endsAt: Date(timeIntervalSinceReferenceDate: 86_400),
            label: "May",
            meter: meter
        )
        meter.readings.append(reading)
        meter.tariffs.append(tariff)
        meter.billingPeriods.append(period)
        let syncService = MeterLibrarySyncService(stateStore: InMemoryMeterLibrarySyncStateStore())

        try syncService.enableSync(for: [meter], libraryID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        XCTAssertEqual(syncService.status, .idle)
        XCTAssertEqual(syncService.currentRole, .owner)
        XCTAssertEqual(syncService.pendingOperations.count, 4)
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertMeter(MeterSyncRecord(meter: meter))))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertTariff(MeterTariffSyncRecord(tariff: tariff)!)))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertBillingPeriod(BillingPeriodSyncRecord(period: period)!)))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertReading(MeterReadingSyncRecord(reading: reading)!)))
    }

    @MainActor
    func testCollaboratorCanOnlyQueueReadingChanges() throws {
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .collaborator,
            libraryID: UUID()
        )

        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            meterID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            value: 12,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        try syncService.enqueue(.upsertReading(readingRecord))

        XCTAssertThrowsError(try syncService.enqueue(.deleteMeter(UUID()))) { error in
            XCTAssertEqual(error as? MeterLibrarySyncError, .permissionDenied(.deleteMeter))
        }
    }

    @MainActor
    func testSyncMergeKeepsLatestReadingEdit() {
        let readingID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let meterID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let local = MeterReadingSyncRecord(
            id: readingID,
            meterID: meterID,
            value: 10,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "Local",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let remote = MeterReadingSyncRecord(
            id: readingID,
            meterID: meterID,
            value: 11,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "Remote",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        let merged = MeterLibrarySyncService.mergeReadings(local: [local], remote: [remote])

        XCTAssertEqual(merged, [remote])
    }

    @MainActor
    func testSyncNowKeepsPendingOperationsUntilDurableCloudHandoffExists() throws {
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .owner,
            libraryID: UUID()
        )
        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            meterID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            value: 21,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        try syncService.enqueue(.upsertReading(readingRecord))

        let result = try syncService.syncNow()

        XCTAssertEqual(result.acceptedOperations, [.upsertReading(readingRecord)])
        XCTAssertEqual(syncService.pendingOperations, [.upsertReading(readingRecord)])
    }

    @MainActor
    func testCollaboratorSyncAcceptsOwnerLibraryChangesButRejectsCollaboratorAdminChanges() throws {
        let meter = Meter(name: "Shared", kind: .water)
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .collaborator,
            libraryID: UUID()
        )
        let ownerOperation = MeterRemoteSyncOperation.verifiedOwnerChange(.upsertMeter(MeterSyncRecord(meter: meter)))
        let collaboratorOperation = MeterRemoteSyncOperation.verifiedCollaboratorChange(.deleteMeter(meter.id))

        let result = try syncService.syncNow(remoteOperations: [ownerOperation, collaboratorOperation])

        XCTAssertEqual(result.acceptedOperations, [ownerOperation.operation])
        XCTAssertEqual(result.rejectedOperations, [collaboratorOperation.operation])
    }

    @MainActor
    func testSyncServiceRestoresPersistedStateAndPendingOperations() throws {
        let store = InMemoryMeterLibrarySyncStateStore()
        let libraryID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            meterID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            value: 31,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        store.saveState(
            MeterLibrarySyncState(
                status: .idle,
                currentRole: .collaborator,
                libraryID: libraryID,
                pendingOperations: [.upsertReading(readingRecord)]
            )
        )

        let syncService = MeterLibrarySyncService(stateStore: store)

        XCTAssertEqual(syncService.status, .idle)
        XCTAssertEqual(syncService.currentRole, .collaborator)
        XCTAssertEqual(syncService.libraryID, libraryID)
        XCTAssertEqual(syncService.pendingOperations, [.upsertReading(readingRecord)])
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

    func testReadingDateInputParserAcceptsCompactDateAndDetectsTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let dateOnly = try XCTUnwrap(ReadingDateInputParser.parse("01062026", calendar: calendar))
        let dateTime = try XCTUnwrap(ReadingDateInputParser.parse("01062026 1430", calendar: calendar))

        XCTAssertEqual(dateOnly.granularity, .dateOnly)
        XCTAssertEqual(calendar.component(.day, from: dateOnly.date), 1)
        XCTAssertEqual(calendar.component(.month, from: dateOnly.date), 6)
        XCTAssertEqual(dateTime.granularity, .dateTime)
        XCTAssertEqual(calendar.component(.hour, from: dateTime.date), 14)
        XCTAssertEqual(calendar.component(.minute, from: dateTime.date), 30)
    }

    func testReadingDateInputParserReservesHyphenForDaySteppingShortcut() {
        XCTAssertNil(ReadingDateInputParser.parse("2026-06-01"))
    }

    func testReadingDateInputParserStepsDaysWithoutChangingTimeDetail() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fallback = try XCTUnwrap(ReadingDateInputParser.parse("01.06.2026 14:30", calendar: calendar))

        let stepped = ReadingDateInputParser.addingDays(1, to: "01.06.2026 14:30", fallback: fallback, calendar: calendar)

        XCTAssertEqual(stepped.granularity, .dateTime)
        XCTAssertEqual(calendar.component(.day, from: stepped.date), 2)
        XCTAssertEqual(calendar.component(.hour, from: stepped.date), 14)
        XCTAssertEqual(calendar.component(.minute, from: stepped.date), 30)
    }

    func testReadingDateInputParserRoundTripsLocalizedDisplayValues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 14, minute: 30))!
        let dateOnlyInput = ReadingDateInput(date: calendar.startOfDay(for: date), granularity: .dateOnly)
        let dateTimeInput = ReadingDateInput(date: date, granularity: .dateTime)

        for locale in [Locale(identifier: "en_US"), Locale(identifier: "de_DE")] {
            let dateOnlyText = ReadingDateInputParser.format(dateOnlyInput, calendar: calendar, locale: locale)
            let dateTimeText = ReadingDateInputParser.format(dateTimeInput, calendar: calendar, locale: locale)
            let parsedDateOnly = try XCTUnwrap(ReadingDateInputParser.parse(dateOnlyText, calendar: calendar, locale: locale))
            let parsedDateTime = try XCTUnwrap(ReadingDateInputParser.parse(dateTimeText, calendar: calendar, locale: locale))

            XCTAssertEqual(parsedDateOnly, dateOnlyInput)
            XCTAssertEqual(parsedDateTime, dateTimeInput)
        }
    }

    func testReadingDateInputParserChangesGranularityWithMidnightFallback() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateTime = try XCTUnwrap(ReadingDateInputParser.parse("01.06.2026 14:30", calendar: calendar))
        let expectedStartOfDay = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!

        let dateOnly = ReadingDateInputParser.changingGranularity(dateTime, to: .dateOnly, calendar: calendar)
        let dateTimeAgain = ReadingDateInputParser.changingGranularity(dateOnly, to: .dateTime, calendar: calendar)
        let unchangedDateTime = ReadingDateInputParser.changingGranularity(dateTime, to: .dateTime, calendar: calendar)

        XCTAssertEqual(dateOnly.granularity, .dateOnly)
        XCTAssertEqual(dateOnly.date, expectedStartOfDay)
        XCTAssertEqual(dateTimeAgain.granularity, .dateTime)
        XCTAssertEqual(dateTimeAgain.date, expectedStartOfDay)
        XCTAssertEqual(unchangedDateTime.date, dateTime.date)
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

    func testPDFReportSelectedScopeIncludesOnlySelectedMeter() {
        let selected = Meter(name: "Kitchen", kind: .electricity)
        let other = Meter(name: "Bath", kind: .water)

        let snapshots = PDFReportGenerator.snapshots(
            meters: [selected, other],
            scope: .selectedMeter(selected.id),
            selectedPeriod: .currentMonth
        )

        XCTAssertEqual(snapshots.map(\.meterID), [selected.id])
    }

    func testPDFReportAllActiveScopeExcludesArchivedMeters() {
        let active = Meter(name: "Kitchen", kind: .electricity)
        let archived = Meter(name: "Old", kind: .custom, isArchived: true)

        let snapshots = PDFReportGenerator.snapshots(
            meters: [archived, active],
            scope: .allActiveMeters,
            selectedPeriod: .currentYear
        )

        XCTAssertEqual(snapshots.map(\.meterID), [active.id])
        XCTAssertEqual(snapshots.first?.period, .currentYear)
    }

    func testPDFReportSnapshotIncludesReadingStatisticsForecastAndCost() throws {
        let calendar = utcCalendar()
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let meter = Meter(name: "Kitchen", kind: .electricity, unit: "kWh", decimalPrecision: 1)
        meter.tariffs.append(MeterTariff(currencyCode: "EUR", unitPrice: 0.30, baseFee: 5, meter: meter))
        meter.readings.append(MeterReading(
            value: 100,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            recordedAtGranularity: .dateOnly,
            meter: meter
        ))
        meter.readings.append(MeterReading(
            value: 140,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!,
            recordedAtGranularity: .dateOnly,
            note: "Manual",
            meter: meter
        ))

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            referenceDate: reference,
            calendar: calendar
        ).first)

        XCTAssertEqual(snapshot.latestReading?.value, 140)
        XCTAssertEqual(snapshot.readingCount, 2)
        XCTAssertNotNil(snapshot.statistics)
        XCTAssertNotNil(snapshot.statistics?.projectedCost)
        XCTAssertNotNil(snapshot.forecast)
        XCTAssertNotNil(snapshot.forecast?.projectedCost)
        XCTAssertEqual(snapshot.recentReadings.first?.note, "Manual")
    }

    func testPDFReportForecastUsesSelectedCurrentScopeOnly() throws {
        let calendar = utcCalendar()
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!, meter: meter))
        meter.readings.append(MeterReading(value: 140, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!, meter: meter))

        let currentSnapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            referenceDate: reference,
            calendar: calendar
        ).first)
        let previousSnapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .previousMonths,
            referenceDate: reference,
            calendar: calendar
        ).first)

        XCTAssertNotNil(currentSnapshot.forecast)
        XCTAssertNil(previousSnapshot.forecast)
    }

    func testPDFReportSnapshotRepresentsInsufficientDataWithoutCrashing() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth
        ).first)

        XCTAssertNil(snapshot.statistics)
        XCTAssertNil(snapshot.forecast)
        XCTAssertEqual(snapshot.readingCount, 1)
    }

    func testPDFReportRecentReadingsAreNewestFirstAndCapped() throws {
        let calendar = utcCalendar()
        let meter = Meter(name: "Kitchen", kind: .electricity)
        for day in 1...25 {
            meter.readings.append(MeterReading(
                value: Double(day),
                recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: day))!,
                recordedAtGranularity: .dateOnly,
                meter: meter
            ))
        }

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            calendar: calendar
        ).first)

        XCTAssertEqual(snapshot.recentReadings.count, PDFReportGenerator.recentReadingLimit)
        XCTAssertEqual(snapshot.recentReadings.first?.value, 25)
        XCTAssertEqual(snapshot.recentReadings.last?.value, 6)
    }

    func testPDFReportSuggestedFileNamesAreSafe() {
        let meter = Meter(name: "Kitchen/Main", kind: .custom)

        XCTAssertEqual(PDFReportGenerator.suggestedFileName(for: .allActiveMeters, meters: [meter]), "meter2-report.pdf")
        XCTAssertEqual(PDFReportGenerator.suggestedFileName(for: .selectedMeter(meter.id), meters: [meter]), "meter2-Kitchen-Main-report.pdf")
    }

    func testPDFReportGeneratorCreatesNonEmptyPDFData() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)

        let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorCreatesValidEmptyAllActivePDF() throws {
        let data = try PDFReportGenerator.pdfData(snapshots: [], scope: .allActiveMeters)

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorHandlesVeryLongReadingNotes() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(
            value: 100,
            recordedAt: Date(timeIntervalSinceReferenceDate: 0),
            note: String(repeating: "Long note ", count: 500),
            meter: meter
        ))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)

        let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorUsesPrintableColorsInDarkAppearance() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var result: Result<Data, Error>?

        darkAppearance.performAsCurrentDrawingAppearance {
            result = Result {
                try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))
            }
        }

        let data = try XCTUnwrap(result).get()

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
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
            tariff: tariff,
            referenceDate: Date(timeIntervalSinceReferenceDate: 3 * 86_400)
        )

        let forecast = try XCTUnwrap(result)
        XCTAssertEqual(forecast.averageDailyConsumption, 10, accuracy: 0.001)
        XCTAssertEqual(forecast.projectedConsumption, 50, accuracy: 0.001)
        XCTAssertEqual(forecast.projectedValue, 150, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(forecast.projectedCost), 27, accuracy: 0.001)
        XCTAssertEqual(forecast.basis, .currentPeriod)
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
            periodEnd: Date(timeIntervalSinceReferenceDate: 5 * 86_400),
            referenceDate: Date(timeIntervalSinceReferenceDate: 4 * 86_400)
        )

        XCTAssertEqual(try XCTUnwrap(result).projectedConsumption, 30, accuracy: 0.001)
    }

    func testProjectionStartsRemainingHorizonAtLatestReadingWhenReadingIsBeforeReferenceDate() throws {
        let readings = [
            MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0)),
            MeterReading(value: 140, recordedAt: Date(timeIntervalSinceReferenceDate: 4 * 86_400))
        ]

        let projection = try XCTUnwrap(MeterAnalytics.projection(
            readings: readings,
            periodStart: Date(timeIntervalSinceReferenceDate: 0),
            periodEnd: Date(timeIntervalSinceReferenceDate: 10 * 86_400),
            referenceDate: Date(timeIntervalSinceReferenceDate: 7 * 86_400)
        ))

        XCTAssertEqual(projection.anchorDate, Date(timeIntervalSinceReferenceDate: 4 * 86_400))
        XCTAssertEqual(projection.currentConsumption, 40, accuracy: 0.001)
        XCTAssertEqual(projection.projectedConsumption, 100, accuracy: 0.001)
    }

    func testProjectionFallsBackToRecentReadingsWhenCurrentPeriodHasTooLittleData() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 4))!),
            MeterReading(value: 160, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 7))!),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!)
        ]
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(-1)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!

        let projection = try XCTUnwrap(MeterAnalytics.projection(
            readings: readings,
            periodStart: periodStart,
            periodEnd: periodEnd,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(projection.basis, .recentReadings)
        XCTAssertEqual(projection.basisReadingCount, 4)
        XCTAssertEqual(projection.quality, .medium)
    }

    func testProjectionFallsBackToHistoricalAverageWhenRecentReadingsAreStale() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 12, day: 1))!),
            MeterReading(value: 160, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!),
            MeterReading(value: 220, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!)
        ]
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(-1)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!

        let projection = try XCTUnwrap(MeterAnalytics.projection(
            readings: readings,
            periodStart: periodStart,
            periodEnd: periodEnd,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(projection.basis, .historicalAverage)
        XCTAssertEqual(projection.quality, .low)
    }

    func testProjectionQualityDropsWhenLatestReadingIsOld() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 120, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!),
            MeterReading(value: 140, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!)
        ]
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(-1)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30))!

        let projection = try XCTUnwrap(MeterAnalytics.projection(
            readings: readings,
            periodStart: periodStart,
            periodEnd: periodEnd,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(projection.quality, .low)
        XCTAssertEqual(projection.nextRecommendedReadingDate, calendar.startOfDay(for: referenceDate))
    }

    func testProjectionQualityDropsForHighlyVariableReadings() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 101, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 2))!),
            MeterReading(value: 160, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!)
        ]
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let periodEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(-1)
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!

        let projection = try XCTUnwrap(MeterAnalytics.projection(
            readings: readings,
            periodStart: periodStart,
            periodEnd: periodEnd,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(projection.quality, .low)
    }

    func testStatisticsPeriodRangesUseRequestedScopes() throws {
        let calendar = utcCalendar()
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!
        let readings = [
            MeterReading(value: 80, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!),
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 5, day: 1))!),
            MeterReading(value: 150, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
        ]

        let month = try XCTUnwrap(MeterAnalytics.statisticsPeriodRange(.currentMonth, containing: reference, readings: readings, calendar: calendar))
        let previousMonths = try XCTUnwrap(MeterAnalytics.statisticsPeriodRange(.previousMonths, containing: reference, readings: readings, calendar: calendar))
        let year = try XCTUnwrap(MeterAnalytics.statisticsPeriodRange(.currentYear, containing: reference, readings: readings, calendar: calendar))
        let previousYears = try XCTUnwrap(MeterAnalytics.statisticsPeriodRange(.previousYears, containing: reference, readings: readings, calendar: calendar))
        let previousYearMonths = MeterAnalytics.statisticsPeriodRanges(.previousYearMonths, containing: reference, readings: readings, calendar: calendar)
        let custom = try XCTUnwrap(MeterAnalytics.statisticsPeriodRange(
            .custom,
            containing: reference,
            readings: readings,
            customStart: calendar.date(from: DateComponents(year: 2026, month: 4, day: 2))!,
            customEnd: calendar.date(from: DateComponents(year: 2026, month: 4, day: 4))!,
            calendar: calendar
        ))

        XCTAssertEqual(month.0, calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        XCTAssertEqual(previousMonths.0, calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        XCTAssertEqual(previousMonths.1, calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!.addingTimeInterval(-1))
        XCTAssertEqual(year.0, calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        XCTAssertEqual(previousYears.0, calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        XCTAssertEqual(previousYears.1, calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!.addingTimeInterval(-1))
        XCTAssertEqual(previousYearMonths.map(\.startsAt), [
            calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!,
            calendar.date(from: DateComponents(year: 2025, month: 5, day: 1))!
        ])
        XCTAssertEqual(custom.0, calendar.date(from: DateComponents(year: 2026, month: 4, day: 2)))
        XCTAssertEqual(custom.1, calendar.date(from: DateComponents(year: 2026, month: 4, day: 5))!.addingTimeInterval(-1))
    }

    func testStatisticsCalculatesInterpolatedCurrentPeriodConsumptionAverageAndCost() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 160, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!)
        ]
        let tariff = MeterTariff(currencyCode: "EUR", unitPrice: 0.5, baseFee: 2)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(for: readings, period: .currentMonth, referenceDate: reference, tariff: tariff, calendar: calendar))

        XCTAssertEqual(statistics.consumption, 60, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(statistics.averageDailyConsumption), 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(statistics.projectedConsumption), 309.999, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(statistics.projectedCost), 156.999, accuracy: 0.01)
        XCTAssertEqual(statistics.projectionBasis, .currentPeriod)
        XCTAssertEqual(statistics.projectionQuality, .medium)
        XCTAssertEqual(statistics.lastConsumptionPace?.consumption, 60)
    }

    func testStatisticsComparesWithPreviousPeriod() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(for: readings, period: .currentMonth, referenceDate: reference, calendar: calendar))
        let comparison = try XCTUnwrap(statistics.comparison)

        XCTAssertEqual(comparison.currentConsumption, 70, accuracy: 0.001)
        XCTAssertEqual(comparison.previousConsumption, 30, accuracy: 0.01)
        XCTAssertEqual(comparison.absoluteDelta, 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(comparison.percentageDelta), 1.333, accuracy: 0.01)
    }

    func testStatisticsSkipsPreviousComparisonWithoutCoveredPreviousPeriod() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 160, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 7))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(for: readings, period: .currentMonth, referenceDate: reference, calendar: calendar))

        XCTAssertNil(statistics.comparison)
        XCTAssertEqual(statistics.comparisonUnavailableReason, .previousPeriodNotCovered)
    }

    func testPreviousYearsStatisticsDoesNotProjectOrCompare() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!),
            MeterReading(value: 150, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 1, day: 11))!),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(for: readings, period: .previousYears, referenceDate: reference, calendar: calendar))

        XCTAssertEqual(statistics.consumption, 100, accuracy: 0.001)
        XCTAssertNil(statistics.projectedConsumption)
        XCTAssertNil(statistics.projectedCost)
        XCTAssertNil(statistics.comparison)
        XCTAssertEqual(statistics.comparisonUnavailableReason, .notComparable)
    }

    func testPreviousYearMonthsStatisticsSumsSameMonthRanges() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 5, day: 1))!),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 6, day: 1))!),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 5, day: 1))!),
            MeterReading(value: 250, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!),
            MeterReading(value: 300, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(for: readings, period: .previousYearMonths, referenceDate: reference, calendar: calendar))

        XCTAssertEqual(statistics.ranges.count, 2)
        XCTAssertEqual(statistics.consumption, 80, accuracy: 0.001)
        XCTAssertNil(statistics.projectedConsumption)
        XCTAssertEqual(statistics.comparisonUnavailableReason, .notComparable)
    }

    func testPeriodOverviewsAverageWeeksMonthsAndYears() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 0, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!),
            MeterReading(value: 70, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 1, day: 8))!),
            MeterReading(value: 140, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!)
        ]
        let range = StatisticsDateRange(
            startsAt: readings[0].recordedAt,
            endsAt: readings[2].recordedAt
        )

        let overviews = MeterAnalytics.periodOverviews(for: readings, ranges: [range], referenceDate: readings[2].recordedAt, calendar: calendar)
        let weekly = try XCTUnwrap(overviews.first { $0.granularity == .week })
        let monthly = try XCTUnwrap(overviews.first { $0.granularity == .month })
        let yearly = try XCTUnwrap(overviews.first { $0.granularity == .year })

        XCTAssertEqual(weekly.periodCount, 3)
        XCTAssertEqual(weekly.averageConsumption, 46.666, accuracy: 0.01)
        XCTAssertEqual(monthly.periodCount, 1)
        XCTAssertEqual(monthly.averageConsumption, 140, accuracy: 0.001)
        XCTAssertEqual(yearly.periodCount, 1)
        XCTAssertEqual(yearly.averageConsumption, 140, accuracy: 0.001)
    }

    func testScopedConsumptionDeltasClipSegmentsToSelectedRange() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!)
        ]
        let range = StatisticsDateRange(
            startsAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            endsAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!.addingTimeInterval(-1)
        )

        let deltas = MeterAnalytics.scopedConsumptionDeltas(from: readings, in: [range])
        let delta = try XCTUnwrap(deltas.first)

        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(delta.startDate, range.startsAt)
        XCTAssertEqual(delta.endDate, readings[1].recordedAt)
        XCTAssertEqual(delta.value, 14, accuracy: 0.001)
    }

    func testPeriodOverviewsSkipBucketsOutsideReadingCoverage() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!)
        ]
        let range = StatisticsDateRange(
            startsAt: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            endsAt: calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!.addingTimeInterval(-1)
        )

        let overviews = MeterAnalytics.periodOverviews(for: readings, ranges: [range], referenceDate: range.endsAt, calendar: calendar)
        let monthly = try XCTUnwrap(overviews.first { $0.granularity == .month })

        XCTAssertEqual(monthly.periodCount, 1)
        XCTAssertEqual(monthly.averageConsumption, 30, accuracy: 0.001)
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
        let reportKeys = [
            "report.menu",
            "report.export.selected",
            "report.print.selected",
            "report.export.allActive",
            "report.print.allActive",
            "report.progress.generating",
            "report.insufficientData",
            "report.forecastUnavailable"
        ]
        for key in reportKeys {
            XCTAssertNotNil(strings[key], "Missing report localization key \(key)")
        }
        let updateKeys = [
            "about.menu",
            "about.title",
            "update.check",
            "update.install",
            "update.releasePage",
            "update.status.checking",
            "update.error.missingInstallerAsset"
        ]
        for key in updateKeys {
            XCTAssertNotNil(strings[key], "Missing update localization key \(key)")
        }
        let uxConsistencyKeys = [
            "accessibility.reading.addForMeter %@",
            "help.shortcut.key.addMeter",
            "help.shortcut.key.addReading",
            "help.shortcut.key.importCSV",
            "help.shortcut.key.exportCSV",
            "help.shortcut.key.help",
            "reading.saveAndNext",
            "save"
        ]
        for key in uxConsistencyKeys {
            XCTAssertNotNil(strings[key], "Missing UX consistency localization key \(key)")
        }

        for key in strings.keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            XCTAssertNotEqual(
                entry["extractionState"] as? String,
                "stale",
                "Stale localization entry for \(key)"
            )
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

    func testReleaseVersionParsesMajorAndMinorOnly() {
        let version = AppReleaseVersion(string: "2026.1")

        XCTAssertEqual(version?.year, 2026)
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 0)
        XCTAssertEqual(version?.description, "2026.1")
    }

    func testReleaseVersionParsesMinorReleaseVariant() {
        let version = AppReleaseVersion(string: "2026.0.3")

        XCTAssertEqual(version?.year, 2026)
        XCTAssertEqual(version?.major, 0)
        XCTAssertEqual(version?.minor, 3)
        XCTAssertEqual(version?.description, "2026.0.3")
    }

    func testReleaseVersionIgnoresLeadingVPrefixAndRejectsInvalidInput() {
        XCTAssertEqual(
            AppReleaseVersion(string: "v2026.1.2"),
            AppReleaseVersion(string: "2026.1.2")
        )
        XCTAssertNil(AppReleaseVersion(string: "2026"))
        XCTAssertNil(AppReleaseVersion(string: "2026.one.2"))
    }

    func testReleaseVersionComparisonTreatsMinorAsNewerThanBaseRelease() {
        let base = AppReleaseVersion(string: "2026.1")
        let patch = AppReleaseVersion(string: "2026.1.2")
        let nextMajor = AppReleaseVersion(string: "2026.2")

        XCTAssertNotNil(base)
        XCTAssertNotNil(patch)
        XCTAssertNotNil(nextMajor)
        XCTAssertLessThan(base!, patch!)
        XCTAssertLessThan(patch!, nextMajor!)
    }

    func testAppUpdateLatestReleaseRequestBypassesCachedReleasePayloads() throws {
        let url = try XCTUnwrap(URL(string: "https://api.github.com/repos/christiankaps/meter2/releases/latest"))

        let request = AppUpdateService.makeLatestReleaseRequest(url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Meter2")
    }

    @MainActor
    func testAppUpdateRetriesWhenNewerReleaseInitiallyMissingInstallerAsset() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.2"))
        let releaseWithoutDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.0.3",
            htmlURL: "https://github.com/christiankaps/meter2/releases/tag/stale-without-dmg",
            assets: []
        )
        let releaseWithDMG = AppUpdateService.GitHubReleaseResponse(
            tagName: "2026.0.3",
            htmlURL: "https://github.com/christiankaps/meter2/releases/tag/fresh-with-dmg",
            assets: [
                .init(
                    name: "Meter2_2026.0.3_43.dmg",
                    browserDownloadURL: "https://github.com/christiankaps/meter2/releases/download/2026.0.3/Meter2_2026.0.3_43.dmg"
                )
            ]
        )
        var responses = [releaseWithoutDMG, releaseWithDMG]
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return responses.removeFirst()
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(sleepCount, 1)
        XCTAssertEqual(info?.latestVersion, AppReleaseVersion(string: "2026.0.3"))
        XCTAssertEqual(info?.assetName, "Meter2_2026.0.3_43.dmg")
        XCTAssertEqual(info?.releasePageURL.absoluteString, "https://github.com/christiankaps/meter2/releases/tag/fresh-with-dmg")
        XCTAssertEqual(
            info?.downloadURL.absoluteString,
            "https://github.com/christiankaps/meter2/releases/download/2026.0.3/Meter2_2026.0.3_43.dmg"
        )
    }

    @MainActor
    func testAppUpdateDoesNotRetryWhenLatestReleaseIsNotNewer() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.3"))
        var fetchCount = 0
        var sleepCount = 0

        let info = try await service.fetchUpdateInfo(
            currentVersion: currentVersion,
            releaseFetcher: {
                fetchCount += 1
                return AppUpdateService.GitHubReleaseResponse(
                    tagName: "2026.0.3",
                    htmlURL: "https://github.com/christiankaps/meter2/releases/tag/2026.0.3",
                    assets: []
                )
            },
            sleep: { _ in
                sleepCount += 1
            }
        )

        XCTAssertNil(info)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    @MainActor
    func testAppUpdateReportsMissingInstallerAfterRetries() async throws {
        let service = AppUpdateService()
        let currentVersion = try XCTUnwrap(AppReleaseVersion(string: "2026.0.2"))
        var fetchCount = 0
        var sleepCount = 0

        do {
            _ = try await service.fetchUpdateInfo(
                currentVersion: currentVersion,
                releaseFetcher: {
                    fetchCount += 1
                    return AppUpdateService.GitHubReleaseResponse(
                        tagName: "2026.0.3",
                        htmlURL: "https://github.com/christiankaps/meter2/releases/tag/2026.0.3",
                        assets: []
                    )
                },
                sleep: { _ in
                    sleepCount += 1
                }
            )
            XCTFail("Expected a missing installer error.")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("DMG") || message.contains("Installer"))
        }

        XCTAssertEqual(fetchCount, 4)
        XCTAssertEqual(sleepCount, 3)
    }

    @MainActor
    func testAppUpdateMountedVolumeURLParsesHdiutilPlist() throws {
        let propertyList: [String: Any] = [
            "system-entities": [
                ["dev-entry": "/dev/disk4"],
                ["mount-point": "/Volumes/Meter2", "volume-kind": "hfs"]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)

        let mountedURL = try AppUpdateService.mountedVolumeURL(fromAttachOutput: data)

        XCTAssertEqual(mountedURL.path, "/Volumes/Meter2")
    }

    @MainActor
    func testAppUpdateProgressFormatsDownloadFraction() {
        let progress = AppUpdateService.UpdateProgress(
            version: AppReleaseVersion(string: "2026.0.3")!,
            phase: .downloading(bytesReceived: 1_024, totalBytes: 2_048)
        )

        XCTAssertTrue(progress.title.contains("2026.0.3"))
        XCTAssertEqual(progress.statusSummary, "50%")
        XCTAssertEqual(progress.fractionCompleted ?? -1, 0.5, accuracy: 0.0001)
    }

    @MainActor
    func testAppUpdateProgressRejectsRegressiveUpdates() {
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .downloading(bytesReceived: 2_048, totalBytes: 4_096),
                over: .mountingInstaller
            )
        )
        XCTAssertFalse(
            AppUpdateService.UpdateProgress.shouldAccept(
                .startingDownload,
                over: .downloading(bytesReceived: 2_048, totalBytes: 4_096)
            )
        )
    }

    @MainActor
    func testAppUpdateProgressSessionIgnoresUpdatesFromOlderSession() {
        let service = AppUpdateService()
        let oldVersion = AppReleaseVersion(string: "2026.0.3")!
        let newVersion = AppReleaseVersion(string: "2026.1")!
        let oldSessionID = service.beginUpdateProgressSession(for: oldVersion)
        _ = service.beginUpdateProgressSession(for: newVersion)

        service.applyUpdateProgress(.downloading(bytesReceived: 1_024, totalBytes: 2_048), version: oldVersion, sessionID: oldSessionID)

        XCTAssertEqual(service.updateProgress?.version, newVersion)
        XCTAssertEqual(service.updateProgress?.phase, .startingDownload)
        service.clearUpdateProgressSession()
    }

    @MainActor
    func testAppUpdateMountDiskImageReportsAttachFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.mountDiskImage(
                at: URL(fileURLWithPath: "/tmp/Meter2.dmg"),
                processRunner: { _, _ in
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: attach failed"]
                    )
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("hdiutil: attach failed"))
        }
    }

    @MainActor
    func testAppUpdateDetachDiskImageRetriesWithForceWhenVolumeIsBusy() throws {
        var recordedArguments: [[String]] = []

        try AppUpdateService.detachDiskImage(
            at: URL(fileURLWithPath: "/Volumes/Meter2", isDirectory: true),
            processRunner: { executablePath, arguments in
                XCTAssertEqual(executablePath, "/usr/bin/hdiutil")
                recordedArguments.append(arguments)

                if recordedArguments.count == 1 {
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 16,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: couldn't unmount disk23"]
                    )
                }

                return Data()
            },
            sleep: { _ in }
        )

        XCTAssertEqual(
            recordedArguments,
            [
                ["detach", "/Volumes/Meter2"],
                ["detach", "-force", "/Volumes/Meter2"]
            ]
        )
    }

    @MainActor
    func testAppUpdateDetachDiskImageDoesNotForceForNonBusyFailures() {
        var recordedArguments: [[String]] = []

        XCTAssertThrowsError(
            try AppUpdateService.detachDiskImage(
                at: URL(fileURLWithPath: "/Volumes/Meter2", isDirectory: true),
                processRunner: { _, arguments in
                    recordedArguments.append(arguments)
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "hdiutil: no such image"]
                    )
                },
                sleep: { _ in }
            )
        )

        XCTAssertEqual(recordedArguments, [["detach", "/Volumes/Meter2"]])
    }

    @MainActor
    func testAppUpdateVerifyCodeSignatureReportsVerificationFailure() {
        XCTAssertThrowsError(
            try AppUpdateService.verifyCodeSignature(
                of: URL(fileURLWithPath: "/tmp/Meter2.app", isDirectory: true),
                expectedBundleIdentifier: AppConfiguration.bundleIdentifier,
                expectedTeamIdentifier: nil,
                processRunner: { _, _ in
                    throw NSError(
                        domain: "Meter2Tests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "code object is not signed at all"]
                    )
                },
                metadataProvider: { _ in
                    XCTFail("Metadata should not be requested when signature verification fails.")
                    return (identifier: nil, teamIdentifier: nil)
                }
            )
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            XCTAssertTrue(message.contains("code object is not signed at all"))
        }
    }

    func testReleaseWorkflowSignsAndVerifiesAppBeforeCreatingDMG() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let workflowURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".github/workflows/release.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("codesign --force --deep --sign - \"$APP_PATH\""))
        XCTAssertTrue(workflow.contains("codesign --verify --deep --strict \"$APP_PATH\""))

        let signingStep = try XCTUnwrap(workflow.range(of: "- name: Sign and verify app"))
        let dmgStep = try XCTUnwrap(workflow.range(of: "- name: Create DMG"))
        XCTAssertLessThan(signingStep.lowerBound, dmgStep.lowerBound)
    }

    @MainActor
    func testAppUpdateInstallerScriptContainsReplaceRelaunchAndRollbackSteps() {
        let script = AppUpdateService.installerScript(
            currentPID: 1234,
            stagedAppURL: URL(fileURLWithPath: "/tmp/Meter2Update/Meter2.app"),
            destinationAppURL: URL(fileURLWithPath: "/Applications/Meter2.app"),
            temporaryRootURL: URL(fileURLWithPath: "/tmp/Meter2Update")
        )

        XCTAssertTrue(script.contains("CURRENT_PID=1234"))
        XCTAssertTrue(script.contains("/usr/bin/ditto"))
        XCTAssertTrue(script.contains("/usr/bin/osascript"))
        XCTAssertTrue(script.contains("/usr/bin/open \"$DESTINATION_APP\""))
        XCTAssertTrue(script.contains("/bin/rm -rf \"$TEMP_ROOT\""))
        XCTAssertTrue(script.contains("if /bin/mv \"$DESTINATION_APP.new\" \"$DESTINATION_APP\"; then"))
        XCTAssertTrue(script.contains("/bin/mv \"$DESTINATION_APP.previous\" \"$DESTINATION_APP\""))
    }

    @MainActor
    func testCustomAboutWindowIsConfiguredForMeter2() {
        Meter2AboutWindowController.shared.show()

        XCTAssertEqual(Meter2AboutWindowController.shared.window?.title, String(localized: "about.title"))
        Meter2AboutWindowController.shared.window?.close()
    }
}
