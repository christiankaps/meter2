import SwiftData
import XCTest
@testable import Meter2

final class Meter2Tests: XCTestCase {
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
