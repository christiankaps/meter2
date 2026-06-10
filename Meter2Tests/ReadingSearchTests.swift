import XCTest

@testable import Meter2

final class ReadingSearchTests: XCTestCase {
    private func makeReadings() -> [MeterReading] {
        let calendar = utcCalendar()
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let second = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        return [
            MeterReading(value: 1200.5, recordedAt: first, recordedAtGranularity: .dateOnly, note: "Initial reading"),
            MeterReading(value: 1242.8, recordedAt: second, recordedAtGranularity: .dateOnly, note: "After vacation")
        ]
    }

    func testFilterReturnsAllReadingsForBlankQuery() {
        let readings = makeReadings()

        XCTAssertEqual(ReadingSearch.filter(readings, query: "", unit: "kWh", precision: 1).count, 2)
        XCTAssertEqual(ReadingSearch.filter(readings, query: "   ", unit: "kWh", precision: 1).count, 2)
    }

    func testFilterMatchesNoteCaseInsensitively() {
        let readings = makeReadings()

        let result = ReadingSearch.filter(readings, query: "VACATION", unit: "kWh", precision: 1)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.note, "After vacation")
    }

    func testFilterMatchesRawValueDigits() {
        let readings = makeReadings()

        let result = ReadingSearch.filter(readings, query: "1242", unit: "kWh", precision: 1)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.value, 1242.8)
    }

    func testFilterMatchesFormattedDateText() {
        let readings = makeReadings()
        let expectedDateText = MeterFormatting.readingDate(readings[1])
        let datePrefix = String(expectedDateText.prefix(5))

        let result = ReadingSearch.filter(readings, query: datePrefix, unit: "kWh", precision: 1)

        XCTAssertTrue(result.contains { $0.value == 1242.8 })
    }

    func testFilterMatchesLocaleFormattedValueText() {
        let readings = makeReadings()
        let formatted = MeterFormatting.value(readings[0].value, unit: "kWh", precision: 1)
        let valueText = String(formatted.prefix(while: { $0 != " " }))

        let result = ReadingSearch.filter(readings, query: valueText, unit: "kWh", precision: 1)

        XCTAssertTrue(result.contains { $0.value == 1200.5 })
    }

    func testFilterMatchesTimeTextOfDateTimeReading() {
        let calendar = utcCalendar()
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 14, minute: 30))!
        let reading = MeterReading(value: 50, recordedAt: date, recordedAtGranularity: .dateTime)
        let dateText = MeterFormatting.readingDate(reading)
        let timeText = String(dateText.suffix(4))

        XCTAssertTrue(ReadingSearch.matches(reading, query: timeText, unit: "kWh", precision: 1))
    }

    func testFilterReturnsEmptyForUnmatchedQuery() {
        let readings = makeReadings()

        XCTAssertTrue(ReadingSearch.filter(readings, query: "does-not-exist", unit: "kWh", precision: 1).isEmpty)
    }
}
