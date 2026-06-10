import XCTest

@testable import Meter2

final class ReadingValidationTests: XCTestCase {
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

    func testDateNormalizationUsesDisplayedMinutePrecision() {
        let date = Date(timeIntervalSinceReferenceDate: 125.75)
        let normalized = MeterAnalytics.normalizedToDisplayedMinute(date, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(normalized.timeIntervalSinceReferenceDate, 120, accuracy: 0.001)
    }
}
