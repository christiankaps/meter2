import Foundation

enum MeterFormatting {
    static func value(_ value: Double, unit: String, precision: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = max(0, precision)
        formatter.maximumFractionDigits = max(0, precision)

        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    static func decimal(_ value: Double, precision: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = precision
        formatter.maximumFractionDigits = precision
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func currency(_ value: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: value)) ?? "\(value) \(currencyCode)"
    }

    static func signedPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func mediumDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func readingDate(_ reading: MeterReading) -> String {
        switch reading.recordedAtGranularity {
        case .dateOnly:
            shortDate(reading.recordedAt)
        case .dateTime:
            mediumDateTime(reading.recordedAt)
        }
    }
}

enum ReadingSearch {
    static func filter(_ readings: [MeterReading], query: String, unit: String, precision: Int) -> [MeterReading] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return readings }
        return readings.filter { matches($0, query: trimmed, unit: unit, precision: precision) }
    }

    static func matches(_ reading: MeterReading, query: String, unit: String, precision: Int) -> Bool {
        let candidates = [
            reading.note,
            MeterFormatting.value(reading.value, unit: unit, precision: precision),
            String(reading.value),
            MeterFormatting.readingDate(reading)
        ]
        return candidates.contains { $0.localizedStandardContains(query) }
    }
}
