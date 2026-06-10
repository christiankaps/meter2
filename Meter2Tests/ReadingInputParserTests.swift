import XCTest

@testable import Meter2

final class ReadingInputParserTests: XCTestCase {
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
}
