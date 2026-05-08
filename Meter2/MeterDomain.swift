import Foundation
import SwiftData

enum MeterKind: String, CaseIterable, Identifiable {
    case electricity
    case gas
    case water
    case heat
    case solar
    case custom

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .electricity:
            String(localized: "meter.kind.electricity")
        case .gas:
            String(localized: "meter.kind.gas")
        case .water:
            String(localized: "meter.kind.water")
        case .heat:
            String(localized: "meter.kind.heat")
        case .solar:
            String(localized: "meter.kind.solar")
        case .custom:
            String(localized: "meter.kind.custom")
        }
    }

    var defaultUnit: String {
        switch self {
        case .electricity, .solar:
            "kWh"
        case .gas:
            "m3"
        case .water:
            "L"
        case .heat:
            "kWh"
        case .custom:
            ""
        }
    }

    var symbolName: String {
        switch self {
        case .electricity:
            "bolt.fill"
        case .gas:
            "flame.fill"
        case .water:
            "drop.fill"
        case .heat:
            "thermometer.medium"
        case .solar:
            "sun.max.fill"
        case .custom:
            "gauge.with.dots.needle.67percent"
        }
    }
}

enum ReadingTimestampGranularity: String, CaseIterable, Identifiable {
    case dateOnly
    case dateTime

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .dateOnly:
            String(localized: "reading.granularity.dateOnly")
        case .dateTime:
            String(localized: "reading.granularity.dateTime")
        }
    }
}

@Model
final class Meter {
    var id: UUID
    var name: String
    var kindRawValue: String
    var location: String
    var unit: String
    var decimalPrecision: Int
    var isArchived: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \MeterReading.meter)
    var readings: [MeterReading]

    @Relationship(deleteRule: .cascade, inverse: \MeterTariff.meter)
    var tariffs: [MeterTariff]

    @Relationship(deleteRule: .cascade, inverse: \BillingPeriod.meter)
    var billingPeriods: [BillingPeriod]

    init(
        id: UUID = UUID(),
        name: String,
        kind: MeterKind,
        location: String = "",
        unit: String? = nil,
        decimalPrecision: Int = 1,
        isArchived: Bool = false,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.location = location
        self.unit = unit ?? kind.defaultUnit
        self.decimalPrecision = decimalPrecision
        self.isArchived = isArchived
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.readings = []
        self.tariffs = []
        self.billingPeriods = []
    }

    var kind: MeterKind {
        get { MeterKind(rawValue: kindRawValue) ?? .custom }
        set {
            kindRawValue = newValue.rawValue
            if unit.isEmpty {
                unit = newValue.defaultUnit
            }
        }
    }

    var sortedReadingsAscending: [MeterReading] {
        readings.sorted { $0.recordedAt < $1.recordedAt }
    }

    var sortedReadingsDescending: [MeterReading] {
        readings.sorted { $0.recordedAt > $1.recordedAt }
    }

    var latestReading: MeterReading? {
        sortedReadingsDescending.first
    }

    var activeTariff: MeterTariff? {
        tariffs.sorted { $0.validFrom > $1.validFrom }.first
    }

    var activeBillingPeriod: BillingPeriod? {
        billingPeriods.sorted { $0.startsAt > $1.startsAt }.first
    }
}

@Model
final class MeterReading {
    var id: UUID
    var value: Double
    var recordedAt: Date
    var recordedAtGranularityRawValue: String?
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var meter: Meter?

    init(
        id: UUID = UUID(),
        value: Double,
        recordedAt: Date,
        recordedAtGranularity: ReadingTimestampGranularity = .dateTime,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        meter: Meter? = nil
    ) {
        self.id = id
        self.value = value
        self.recordedAt = recordedAt
        self.recordedAtGranularityRawValue = recordedAtGranularity.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.meter = meter
    }

    var recordedAtGranularity: ReadingTimestampGranularity {
        get { ReadingTimestampGranularity(rawValue: recordedAtGranularityRawValue ?? "") ?? .dateTime }
        set { recordedAtGranularityRawValue = newValue.rawValue }
    }
}

@Model
final class MeterTariff {
    var id: UUID
    var currencyCode: String
    var unitPrice: Double
    var baseFee: Double
    var validFrom: Date
    var validUntil: Date?
    var meter: Meter?

    init(
        id: UUID = UUID(),
        currencyCode: String = Locale.current.currency?.identifier ?? "EUR",
        unitPrice: Double = 0,
        baseFee: Double = 0,
        validFrom: Date = Date(),
        validUntil: Date? = nil,
        meter: Meter? = nil
    ) {
        self.id = id
        self.currencyCode = currencyCode
        self.unitPrice = unitPrice
        self.baseFee = baseFee
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.meter = meter
    }
}

@Model
final class BillingPeriod {
    var id: UUID
    var startsAt: Date
    var endsAt: Date
    var label: String
    var meter: Meter?

    init(
        id: UUID = UUID(),
        startsAt: Date,
        endsAt: Date,
        label: String = "",
        meter: Meter? = nil
    ) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.label = label
        self.meter = meter
    }
}

struct ConsumptionDelta: Identifiable, Equatable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let value: Double

    var days: Double {
        max(endDate.timeIntervalSince(startDate) / 86_400, 1)
    }
}

enum ReadingValidationIssue: String, Equatable {
    case negativeValue
    case duplicateTimestamp
    case lowerThanPrevious
    case higherThanNext
    case futureDate
    case unusualJump

    var isBlocking: Bool {
        switch self {
        case .negativeValue, .duplicateTimestamp:
            true
        case .lowerThanPrevious, .higherThanNext, .futureDate, .unusualJump:
            false
        }
    }

    var localizedMessage: String {
        switch self {
        case .negativeValue:
            String(localized: "validation.negativeValue")
        case .duplicateTimestamp:
            String(localized: "validation.duplicateTimestamp")
        case .lowerThanPrevious:
            String(localized: "validation.lowerThanPrevious")
        case .higherThanNext:
            String(localized: "validation.higherThanNext")
        case .futureDate:
            String(localized: "validation.futureDate")
        case .unusualJump:
            String(localized: "validation.unusualJump")
        }
    }
}

struct ReadingValidationResult: Equatable {
    var issues: [ReadingValidationIssue]

    var blockingIssues: [ReadingValidationIssue] {
        issues.filter(\.isBlocking)
    }

    var warnings: [ReadingValidationIssue] {
        issues.filter { !$0.isBlocking }
    }

    var canSave: Bool {
        blockingIssues.isEmpty
    }
}

struct ForecastResult: Equatable {
    let startsAt: Date
    let endsAt: Date
    let currentValue: Double
    let projectedValue: Double
    let projectedConsumption: Double
    let projectedCost: Double?
    let averageDailyConsumption: Double
}

enum MeterAnalytics {
    static func normalizedForStorage(
        _ date: Date,
        granularity: ReadingTimestampGranularity,
        calendar: Calendar = .current
    ) -> Date {
        switch granularity {
        case .dateOnly:
            calendar.startOfDay(for: date)
        case .dateTime:
            normalizedToDisplayedMinute(date, calendar: calendar)
        }
    }

    static func readingsConflict(
        _ firstDate: Date,
        _ firstGranularity: ReadingTimestampGranularity,
        _ secondDate: Date,
        _ secondGranularity: ReadingTimestampGranularity,
        calendar: Calendar = .current
    ) -> Bool {
        if firstGranularity == .dateOnly || secondGranularity == .dateOnly {
            return calendar.isDate(firstDate, inSameDayAs: secondDate)
        }

        return normalizedToDisplayedMinute(firstDate, calendar: calendar) == normalizedToDisplayedMinute(secondDate, calendar: calendar)
    }

    static func normalizedToDisplayedMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    static func sortedReadingsAscending(_ readings: [MeterReading]) -> [MeterReading] {
        readings.sorted { $0.recordedAt < $1.recordedAt }
    }

    static func sortedReadingsDescending(_ readings: [MeterReading]) -> [MeterReading] {
        readings.sorted { $0.recordedAt > $1.recordedAt }
    }

    static func consumptionDeltas(from readings: [MeterReading]) -> [ConsumptionDelta] {
        let sortedReadings = sortedReadingsAscending(readings)
        guard sortedReadings.count >= 2 else { return [] }

        return zip(sortedReadings, sortedReadings.dropFirst()).map { previous, current in
            ConsumptionDelta(
                startDate: previous.recordedAt,
                endDate: current.recordedAt,
                value: current.value - previous.value
            )
        }
    }

    static func averageDailyConsumption(from readings: [MeterReading]) -> Double? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard let first = sortedReadings.first, let last = sortedReadings.last, first.id != last.id else {
            return nil
        }

        let days = last.recordedAt.timeIntervalSince(first.recordedAt) / 86_400
        guard days > 0 else { return nil }

        return (last.value - first.value) / days
    }

    static func lastConsumptionDelta(from readings: [MeterReading]) -> ConsumptionDelta? {
        consumptionDeltas(from: readings).last
    }

    static func estimatedValue(at date: Date, readings: [MeterReading]) -> Double? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard let first = sortedReadings.first else { return nil }

        if date <= first.recordedAt {
            return first.value
        }

        guard let last = sortedReadings.last else { return nil }
        if date >= last.recordedAt {
            return last.value
        }

        if let exactReading = sortedReadings.first(where: { $0.recordedAt == date }) {
            return exactReading.value
        }

        guard
            let previous = sortedReadings.last(where: { $0.recordedAt <= date }),
            let next = sortedReadings.first(where: { $0.recordedAt >= date }),
            next.recordedAt > previous.recordedAt
        else {
            return nil
        }

        let elapsed = date.timeIntervalSince(previous.recordedAt)
        let duration = next.recordedAt.timeIntervalSince(previous.recordedAt)
        let progress = elapsed / duration
        return previous.value + (next.value - previous.value) * progress
    }

    static func defaultBillingPeriod(containing date: Date, calendar: Calendar = .current) -> (Date, Date) {
        let interval = calendar.dateInterval(of: .month, for: date)
        let startsAt = interval?.start ?? date
        let endsAt = interval?.end.addingTimeInterval(-1) ?? date
        return (startsAt, endsAt)
    }

    static func forecast(
        readings: [MeterReading],
        periodStart: Date,
        periodEnd: Date,
        tariff: MeterTariff? = nil
    ) -> ForecastResult? {
        guard
            let averageDailyConsumption = averageDailyConsumption(from: readings),
            let latestReading = sortedReadingsAscending(readings).last,
            periodEnd > latestReading.recordedAt
        else {
            return nil
        }

        let sortedReadings = sortedReadingsAscending(readings)
        let periodStartValue = estimatedValue(at: periodStart, readings: sortedReadings) ?? latestReading.value
        let currentPeriodConsumption = latestReading.recordedAt >= periodStart
            ? max(latestReading.value - periodStartValue, 0)
            : 0
        let projectionStart = max(latestReading.recordedAt, periodStart)
        let remainingDays = max(periodEnd.timeIntervalSince(projectionStart) / 86_400, 0)
        let projectedRemainingConsumption = max(averageDailyConsumption * remainingDays, 0)
        let projectedConsumption = currentPeriodConsumption + projectedRemainingConsumption
        let projectedValue = latestReading.value + max(averageDailyConsumption * periodEnd.timeIntervalSince(latestReading.recordedAt) / 86_400, 0)
        let projectedCost = tariff.map { projectedConsumption * $0.unitPrice + $0.baseFee }

        return ForecastResult(
            startsAt: periodStart,
            endsAt: periodEnd,
            currentValue: latestReading.value,
            projectedValue: projectedValue,
            projectedConsumption: projectedConsumption,
            projectedCost: projectedCost,
            averageDailyConsumption: averageDailyConsumption
        )
    }

    static func validateReading(
        value: Double,
        recordedAt: Date,
        granularity: ReadingTimestampGranularity = .dateTime,
        existingReadings: [MeterReading],
        editingReadingID: UUID? = nil,
        now: Date = Date()
    ) -> ReadingValidationResult {
        var issues: [ReadingValidationIssue] = []
        let normalizedRecordedAt = normalizedForStorage(recordedAt, granularity: granularity)
        let comparableReadings = existingReadings.filter { $0.id != editingReadingID }

        if value < 0 {
            issues.append(.negativeValue)
        }

        if comparableReadings.contains(where: {
            readingsConflict($0.recordedAt, $0.recordedAtGranularity, normalizedRecordedAt, granularity)
        }) {
            issues.append(.duplicateTimestamp)
        }

        if normalizedRecordedAt > now {
            issues.append(.futureDate)
        }

        let sortedComparableReadings = sortedReadingsAscending(comparableReadings)
        if let previous = sortedComparableReadings.last(where: { $0.recordedAt < normalizedRecordedAt }) {
            let previousDelta = value - previous.value
            if value < previous.value {
                issues.append(.lowerThanPrevious)
            }

            let deltas = consumptionDeltas(from: comparableReadings)
                .map(\.value)
                .filter { $0 > 0 }

            if !deltas.isEmpty {
                let averageDelta = deltas.reduce(0, +) / Double(deltas.count)
                if averageDelta > 0, previousDelta > averageDelta * 5 {
                    issues.append(.unusualJump)
                }
            }
        }

        if let next = sortedComparableReadings.first(where: { $0.recordedAt > normalizedRecordedAt }), value > next.value {
            issues.append(.higherThanNext)
        }

        return ReadingValidationResult(issues: issues)
    }
}
