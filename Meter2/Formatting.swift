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

    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func mediumDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
