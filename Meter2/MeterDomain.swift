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

enum ReadingTimestampGranularity: String, CaseIterable, Codable, Identifiable {
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

struct ConsumptionAnomaly: Equatable, Identifiable {
    enum Kind: Equatable {
        case unusuallyHigh
        case unusuallyLow
        case decrease
    }

    let id = UUID()
    let startDate: Date
    let endDate: Date
    let dailyRate: Double
    let typicalDailyRate: Double
    let kind: Kind

    var ratioToTypical: Double {
        guard typicalDailyRate > 0 else { return 0 }
        return dailyRate / typicalDailyRate
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

enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case currentMonth
    case previousMonths
    case previousYearMonths
    case currentYear
    case previousYears
    case custom

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .currentMonth:
            String(localized: "statistics.period.currentMonth")
        case .previousMonths:
            String(localized: "statistics.period.previousMonths")
        case .previousYearMonths:
            String(localized: "statistics.period.previousYearMonths")
        case .currentYear:
            String(localized: "statistics.period.currentYear")
        case .previousYears:
            String(localized: "statistics.period.previousYears")
        case .custom:
            String(localized: "statistics.period.custom")
        }
    }
}

struct StatisticsDateRange: Equatable {
    let startsAt: Date
    let endsAt: Date

    var durationInDays: Double {
        max(endsAt.timeIntervalSince(startsAt) / 86_400, 0)
    }

    func contains(_ date: Date) -> Bool {
        date >= startsAt && date <= endsAt
    }
}

struct MeterPeriodComparison: Equatable {
    let currentConsumption: Double
    let previousConsumption: Double
    let absoluteDelta: Double
    let percentageDelta: Double?
}

enum ProjectionBasis: String, Equatable {
    case currentPeriod
    case recentReadings
    case historicalAverage

    var localizedName: String {
        switch self {
        case .currentPeriod:
            String(localized: "projection.basis.currentPeriod")
        case .recentReadings:
            String(localized: "projection.basis.recentReadings")
        case .historicalAverage:
            String(localized: "projection.basis.historicalAverage")
        }
    }
}

enum ProjectionQuality: String, Equatable {
    case high
    case medium
    case low

    var localizedName: String {
        switch self {
        case .high:
            String(localized: "projection.quality.high")
        case .medium:
            String(localized: "projection.quality.medium")
        case .low:
            String(localized: "projection.quality.low")
        }
    }
}

enum StatisticsUnavailableReason: String, Equatable {
    case notComparable
    case previousPeriodNotCovered
    case notEnoughData

    var localizedText: String {
        switch self {
        case .notComparable:
            String(localized: "statistics.unavailable.notComparable")
        case .previousPeriodNotCovered:
            String(localized: "statistics.unavailable.previousPeriodNotCovered")
        case .notEnoughData:
            String(localized: "statistics.unavailable.notEnoughData")
        }
    }
}

struct ConsumptionPace: Equatable {
    let consumption: Double
    let averageDailyConsumption: Double
    let startsAt: Date
    let endsAt: Date
}

struct ProjectionResult: Equatable {
    let startsAt: Date
    let endsAt: Date
    let anchorDate: Date
    let currentValue: Double
    let projectedValue: Double
    let currentConsumption: Double
    let projectedConsumption: Double
    let projectedCost: Double?
    let averageDailyConsumption: Double
    let basis: ProjectionBasis
    let quality: ProjectionQuality
    let basisDayCount: Double
    let basisReadingCount: Int
    let nextRecommendedReadingDate: Date?
}

struct ForecastResult: Equatable {
    let startsAt: Date
    let endsAt: Date
    let anchorDate: Date
    let currentValue: Double
    let projectedValue: Double
    let projectedConsumption: Double
    let projectedCost: Double?
    let averageDailyConsumption: Double
    let basis: ProjectionBasis
    let quality: ProjectionQuality
    let basisDayCount: Double
    let basisReadingCount: Int
    let nextRecommendedReadingDate: Date?
}

struct MeterStatisticsResult: Equatable {
    let period: StatisticsPeriod
    let startsAt: Date
    let endsAt: Date
    let ranges: [StatisticsDateRange]
    let consumption: Double
    let averageDailyConsumption: Double?
    let lastConsumptionPace: ConsumptionPace?
    let projectedConsumption: Double?
    let projectedCost: Double?
    let projectionBasis: ProjectionBasis?
    let projectionQuality: ProjectionQuality?
    let projectionBasisDayCount: Double?
    let projectionBasisReadingCount: Int?
    let nextRecommendedReadingDate: Date?
    let comparison: MeterPeriodComparison?
    let comparisonUnavailableReason: StatisticsUnavailableReason?
}

enum StatisticsAggregationGranularity: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .week:
            String(localized: "statistics.aggregation.week")
        case .month:
            String(localized: "statistics.aggregation.month")
        case .year:
            String(localized: "statistics.aggregation.year")
        }
    }

    fileprivate var calendarComponent: Calendar.Component {
        switch self {
        case .week:
            .weekOfYear
        case .month:
            .month
        case .year:
            .year
        }
    }
}

struct StatisticsPeriodOverview: Equatable {
    let granularity: StatisticsAggregationGranularity
    let periodCount: Int
    let totalConsumption: Double
    let averageConsumption: Double
    let startsAt: Date
    let endsAt: Date
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

    /// Flags consumption segments that deviate strongly from the meter's
    /// typical daily rate. The typical rate is the median segment rate, so a
    /// few extreme segments cannot hide themselves by skewing the baseline.
    /// Negative segments are always reported as decreases, never as
    /// unusually low usage. Results are in chronological order.
    static func consumptionAnomalies(
        from readings: [MeterReading],
        minimumSegments: Int = 5,
        highRatio: Double = 2.5,
        lowRatio: Double = 0.25
    ) -> [ConsumptionAnomaly] {
        let deltas = consumptionDeltas(from: readings)
        guard deltas.count >= minimumSegments else { return [] }

        let rates = deltas.map { $0.value / $0.days }
        let sortedRates = rates.sorted()
        let middle = sortedRates.count / 2
        let median = sortedRates.count.isMultiple(of: 2)
            ? (sortedRates[middle - 1] + sortedRates[middle]) / 2
            : sortedRates[middle]
        guard median > 0 else { return [] }

        return zip(deltas, rates).compactMap { delta, rate in
            let kind: ConsumptionAnomaly.Kind
            if delta.value < 0 {
                kind = .decrease
            } else if rate >= median * highRatio {
                kind = .unusuallyHigh
            } else if rate <= median * lowRatio {
                kind = .unusuallyLow
            } else {
                return nil
            }
            return ConsumptionAnomaly(
                startDate: delta.startDate,
                endDate: delta.endDate,
                dailyRate: rate,
                typicalDailyRate: median,
                kind: kind
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

    static func lastConsumptionPace(from readings: [MeterReading]) -> ConsumptionPace? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard sortedReadings.count >= 2,
              let previous = sortedReadings.dropLast().last,
              let current = sortedReadings.last else {
            return nil
        }

        let days = current.recordedAt.timeIntervalSince(previous.recordedAt) / 86_400
        guard days > 0 else { return nil }

        let consumption = max(current.value - previous.value, 0)
        return ConsumptionPace(
            consumption: consumption,
            averageDailyConsumption: consumption / days,
            startsAt: previous.recordedAt,
            endsAt: current.recordedAt
        )
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

    static func statisticsPeriodRange(
        _ period: StatisticsPeriod,
        containing date: Date,
        readings: [MeterReading] = [],
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> (Date, Date)? {
        let ranges = statisticsPeriodRanges(
            period,
            containing: date,
            readings: readings,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar
        )
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return (first.startsAt, last.endsAt)
    }

    static func statisticsPeriodRanges(
        _ period: StatisticsPeriod,
        containing date: Date,
        readings: [MeterReading] = [],
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> [StatisticsDateRange] {
        switch period {
        case .currentMonth:
            let range = dateIntervalRange(calendar.dateInterval(of: .month, for: date), fallback: date)
            return [StatisticsDateRange(startsAt: range.0, endsAt: range.1)]
        case .previousMonths:
            guard let currentMonth = calendar.dateInterval(of: .month, for: date),
                  let currentYear = calendar.dateInterval(of: .year, for: date),
                  currentMonth.start > currentYear.start else { return [] }
            return [StatisticsDateRange(startsAt: currentYear.start, endsAt: currentMonth.start.addingTimeInterval(-1))]
        case .previousYearMonths:
            let sortedReadings = sortedReadingsAscending(readings)
            guard let firstYear = sortedReadings.first.map({ calendar.component(.year, from: $0.recordedAt) }) else { return [] }
            let currentYear = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            guard firstYear < currentYear else { return [] }
            return (firstYear..<currentYear).compactMap { year in
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = 1
                guard let monthStart = calendar.date(from: components),
                      let interval = calendar.dateInterval(of: .month, for: monthStart) else { return nil }
                return StatisticsDateRange(startsAt: interval.start, endsAt: interval.end.addingTimeInterval(-1))
            }
        case .currentYear:
            let range = dateIntervalRange(calendar.dateInterval(of: .year, for: date), fallback: date)
            return [StatisticsDateRange(startsAt: range.0, endsAt: range.1)]
        case .previousYears:
            let sortedReadings = sortedReadingsAscending(readings)
            guard let firstReading = sortedReadings.first,
                  let currentYear = calendar.dateInterval(of: .year, for: date),
                  let firstYear = calendar.dateInterval(of: .year, for: firstReading.recordedAt),
                  firstYear.start < currentYear.start else { return [] }
            return [StatisticsDateRange(startsAt: firstYear.start, endsAt: currentYear.start.addingTimeInterval(-1))]
        case .custom:
            guard let customStart, let customEnd else { return [] }
            let start = min(customStart, customEnd)
            let end = max(customStart, customEnd)
            return [StatisticsDateRange(startsAt: calendar.startOfDay(for: start), endsAt: endOfDay(for: end, calendar: calendar))]
        }
    }

    static func previousStatisticsPeriodRange(
        for period: StatisticsPeriod,
        currentStart: Date,
        currentEnd: Date,
        calendar: Calendar = .current
    ) -> (Date, Date)? {
        switch period {
        case .currentMonth:
            guard let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart),
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousStart, previousEnd)
        case .currentYear:
            guard let previousStart = calendar.date(byAdding: .year, value: -1, to: currentStart),
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousStart, previousEnd)
        case .custom:
            let duration = currentEnd.timeIntervalSince(currentStart)
            guard duration > 0,
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousEnd.addingTimeInterval(-duration), previousEnd)
        case .previousMonths, .previousYearMonths, .previousYears:
            return nil
        }
    }

    static func consumption(
        from readings: [MeterReading],
        periodStart: Date,
        periodEnd: Date
    ) -> Double? {
        guard periodEnd >= periodStart,
              let startValue = estimatedValue(at: periodStart, readings: readings),
              let endValue = estimatedValue(at: periodEnd, readings: readings) else {
            return nil
        }

        return max(endValue - startValue, 0)
    }

    static func projection(
        readings: [MeterReading],
        periodStart: Date,
        periodEnd: Date,
        referenceDate: Date = Date(),
        tariff: MeterTariff? = nil,
        calendar: Calendar = .current
    ) -> ProjectionResult? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard sortedReadings.count >= 2,
              periodEnd > periodStart else {
            return nil
        }

        let currentEnd = min(max(referenceDate, periodStart), periodEnd)
        let hasReadingAfterCurrentEnd = sortedReadings.contains { $0.recordedAt > currentEnd }
        let latestReadingAtOrBeforeCurrentEnd = sortedReadings.last(where: { $0.recordedAt <= currentEnd })
        let anchorDate: Date
        if hasReadingAfterCurrentEnd {
            anchorDate = currentEnd
        } else if let latestReadingAtOrBeforeCurrentEnd {
            anchorDate = min(max(latestReadingAtOrBeforeCurrentEnd.recordedAt, periodStart), currentEnd)
        } else {
            anchorDate = currentEnd
        }

        guard let currentValue = estimatedValue(at: anchorDate, readings: sortedReadings),
              let currentConsumption = consumption(from: sortedReadings, periodStart: periodStart, periodEnd: anchorDate),
              let projectionBasis = projectionBasis(
                readings: sortedReadings,
                periodStart: periodStart,
                currentEnd: anchorDate,
                referenceDate: currentEnd,
                currentConsumption: currentConsumption
              ) else {
            return nil
        }

        let remainingDays = max(periodEnd.timeIntervalSince(anchorDate) / 86_400, 0)
        let projectedRemainingConsumption = max(projectionBasis.averageDailyConsumption * remainingDays, 0)
        let projectedConsumption = currentConsumption + projectedRemainingConsumption
        let projectedValue = currentValue + projectedRemainingConsumption
        let projectedCost = tariff.map { projectedConsumption * $0.unitPrice + $0.baseFee }
        let quality = projectionQuality(
            readings: projectionBasis.readings,
            basis: projectionBasis.basis,
            referenceDate: currentEnd
        )

        return ProjectionResult(
            startsAt: periodStart,
            endsAt: periodEnd,
            anchorDate: anchorDate,
            currentValue: currentValue,
            projectedValue: projectedValue,
            currentConsumption: currentConsumption,
            projectedConsumption: projectedConsumption,
            projectedCost: projectedCost,
            averageDailyConsumption: projectionBasis.averageDailyConsumption,
            basis: projectionBasis.basis,
            quality: quality,
            basisDayCount: projectionBasis.dayCount,
            basisReadingCount: projectionBasis.readings.count,
            nextRecommendedReadingDate: recommendedReadingDate(for: quality, referenceDate: currentEnd, calendar: calendar)
        )
    }

    static func statistics(
        for readings: [MeterReading],
        period: StatisticsPeriod,
        referenceDate: Date = Date(),
        tariff: MeterTariff? = nil,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> MeterStatisticsResult? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard sortedReadings.count >= 2,
              let range = statisticsPeriodRange(
                period,
                containing: referenceDate,
                readings: sortedReadings,
                customStart: customStart,
                customEnd: customEnd,
                calendar: calendar
              ) else {
            return nil
        }
        let ranges = statisticsPeriodRanges(
            period,
            containing: referenceDate,
            readings: sortedReadings,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar
        )
        guard !ranges.isEmpty else { return nil }

        let effectiveRanges = ranges.map { effectiveRange($0, referenceDate: referenceDate) }
        let rangeConsumptions = effectiveRanges.compactMap {
            consumption(from: sortedReadings, periodStart: $0.startsAt, periodEnd: $0.endsAt)
        }
        guard rangeConsumptions.count == effectiveRanges.count else {
            return nil
        }

        let periodConsumption = rangeConsumptions.reduce(0, +)
        let elapsedDays = effectiveRanges.reduce(0) { $0 + $1.durationInDays }
        let averageDailyConsumption = elapsedDays > 0 ? periodConsumption / elapsedDays : nil
        let projectionRange = ranges.count == 1 && ranges[0].contains(referenceDate) ? ranges[0] : nil
        let projectedResult = projectionRange.flatMap {
            projection(
                readings: sortedReadings,
                periodStart: $0.startsAt,
                periodEnd: $0.endsAt,
                referenceDate: referenceDate,
                tariff: tariff,
                calendar: calendar
            )
        }
        let firstReadingDate = sortedReadings[0].recordedAt
        let lastReadingDate = sortedReadings[sortedReadings.count - 1].recordedAt
        let comparisonRange = previousStatisticsPeriodRange(for: period, currentStart: range.0, currentEnd: range.1, calendar: calendar)
        var comparisonUnavailableReason: StatisticsUnavailableReason?
        let comparison = comparisonRange.flatMap { previousRange -> MeterPeriodComparison? in
            guard firstReadingDate <= previousRange.0, lastReadingDate >= previousRange.1 else {
                comparisonUnavailableReason = .previousPeriodNotCovered
                return nil
            }

            guard let previousConsumption = MeterAnalytics.consumption(from: sortedReadings, periodStart: previousRange.0, periodEnd: previousRange.1) else {
                comparisonUnavailableReason = .notEnoughData
                return nil
            }

            let absoluteDelta = periodConsumption - previousConsumption
            let percentageDelta = previousConsumption > 0 ? absoluteDelta / previousConsumption : nil
            return MeterPeriodComparison(
                currentConsumption: periodConsumption,
                previousConsumption: previousConsumption,
                absoluteDelta: absoluteDelta,
                percentageDelta: percentageDelta
            )
        }
        if comparisonRange == nil {
            comparisonUnavailableReason = .notComparable
        }

        return MeterStatisticsResult(
            period: period,
            startsAt: range.0,
            endsAt: range.1,
            ranges: ranges,
            consumption: periodConsumption,
            averageDailyConsumption: averageDailyConsumption,
            lastConsumptionPace: lastConsumptionPace(from: sortedReadings),
            projectedConsumption: projectedResult?.projectedConsumption,
            projectedCost: projectedResult?.projectedCost,
            projectionBasis: projectedResult?.basis,
            projectionQuality: projectedResult?.quality,
            projectionBasisDayCount: projectedResult?.basisDayCount,
            projectionBasisReadingCount: projectedResult?.basisReadingCount,
            nextRecommendedReadingDate: projectedResult?.nextRecommendedReadingDate,
            comparison: comparison,
            comparisonUnavailableReason: comparison == nil ? comparisonUnavailableReason : nil
        )
    }

    static func periodOverviews(
        for readings: [MeterReading],
        ranges: [StatisticsDateRange],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [StatisticsPeriodOverview] {
        StatisticsAggregationGranularity.allCases.compactMap {
            periodOverview(for: readings, ranges: ranges, granularity: $0, referenceDate: referenceDate, calendar: calendar)
        }
    }

    static func readings(
        _ readings: [MeterReading],
        in ranges: [StatisticsDateRange]
    ) -> [MeterReading] {
        readings.filter { reading in
            ranges.contains { $0.contains(reading.recordedAt) }
        }
    }

    static func scopedConsumptionDeltas(
        from readings: [MeterReading],
        in ranges: [StatisticsDateRange]
    ) -> [ConsumptionDelta] {
        let sortedReadings = sortedReadingsAscending(readings)
        let deltas = consumptionDeltas(from: sortedReadings)
        return deltas.flatMap { delta -> [ConsumptionDelta] in
            ranges.compactMap { range in
                let start = max(delta.startDate, range.startsAt)
                let end = min(delta.endDate, range.endsAt)
                guard end > start,
                      let value = consumption(from: sortedReadings, periodStart: start, periodEnd: end) else {
                    return nil
                }
                return ConsumptionDelta(startDate: start, endDate: end, value: value)
            }
        }
    }

    private static func periodOverview(
        for readings: [MeterReading],
        ranges: [StatisticsDateRange],
        granularity: StatisticsAggregationGranularity,
        referenceDate: Date,
        calendar: Calendar
    ) -> StatisticsPeriodOverview? {
        let sortedRanges = ranges.sorted { $0.startsAt < $1.startsAt }
        let coveredRange = coveredReadingRange(for: readings)
        let buckets = sortedRanges.flatMap {
            bucketRanges(in: effectiveRange($0, referenceDate: referenceDate), granularity: granularity, calendar: calendar)
        }.filter { bucket in
            guard let coveredRange else { return false }
            return coveredRange.contains(bucket.startsAt) && coveredRange.contains(bucket.endsAt)
        }
        let consumptions = buckets.compactMap {
            consumption(from: readings, periodStart: $0.startsAt, periodEnd: $0.endsAt)
        }

        guard consumptions.count == buckets.count, !consumptions.isEmpty,
              let first = buckets.first,
              let last = buckets.last else {
            return nil
        }

        let total = consumptions.reduce(0, +)
        return StatisticsPeriodOverview(
            granularity: granularity,
            periodCount: consumptions.count,
            totalConsumption: total,
            averageConsumption: total / Double(consumptions.count),
            startsAt: first.startsAt,
            endsAt: last.endsAt
        )
    }

    private static func bucketRanges(
        in range: StatisticsDateRange,
        granularity: StatisticsAggregationGranularity,
        calendar: Calendar
    ) -> [StatisticsDateRange] {
        guard range.endsAt >= range.startsAt,
              var interval = calendar.dateInterval(of: granularity.calendarComponent, for: range.startsAt) else {
            return []
        }

        var buckets: [StatisticsDateRange] = []
        while interval.start <= range.endsAt {
            let start = max(interval.start, range.startsAt)
            let end = min(interval.end.addingTimeInterval(-1), range.endsAt)
            if end > start {
                buckets.append(StatisticsDateRange(startsAt: start, endsAt: end))
            }

            guard let nextStart = calendar.date(byAdding: granularity.calendarComponent, value: 1, to: interval.start),
                  let nextInterval = calendar.dateInterval(of: granularity.calendarComponent, for: nextStart),
                  nextInterval.start > interval.start else {
                break
            }
            interval = nextInterval
        }

        return buckets
    }

    private static func coveredReadingRange(for readings: [MeterReading]) -> StatisticsDateRange? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard let first = sortedReadings.first, let last = sortedReadings.last, last.recordedAt > first.recordedAt else {
            return nil
        }
        return StatisticsDateRange(startsAt: first.recordedAt, endsAt: last.recordedAt)
    }

    static func forecast(
        readings: [MeterReading],
        periodStart: Date,
        periodEnd: Date,
        tariff: MeterTariff? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ForecastResult? {
        guard let projection = projection(
            readings: readings,
            periodStart: periodStart,
            periodEnd: periodEnd,
            referenceDate: referenceDate,
            tariff: tariff,
            calendar: calendar
        ) else { return nil }

        return ForecastResult(
            startsAt: periodStart,
            endsAt: periodEnd,
            anchorDate: projection.anchorDate,
            currentValue: projection.currentValue,
            projectedValue: projection.projectedValue,
            projectedConsumption: projection.projectedConsumption,
            projectedCost: projection.projectedCost,
            averageDailyConsumption: projection.averageDailyConsumption,
            basis: projection.basis,
            quality: projection.quality,
            basisDayCount: projection.basisDayCount,
            basisReadingCount: projection.basisReadingCount,
            nextRecommendedReadingDate: projection.nextRecommendedReadingDate
        )
    }

    private struct ProjectionBasisCandidate {
        let basis: ProjectionBasis
        let averageDailyConsumption: Double
        let dayCount: Double
        let readings: [MeterReading]
    }

    private static func projectionBasis(
        readings: [MeterReading],
        periodStart: Date,
        currentEnd: Date,
        referenceDate: Date,
        currentConsumption: Double
    ) -> ProjectionBasisCandidate? {
        let currentPeriodReadings = readings.filter {
            $0.recordedAt >= periodStart && $0.recordedAt <= currentEnd
        }
        let elapsedDays = max(currentEnd.timeIntervalSince(periodStart) / 86_400, 0)
        if currentPeriodReadings.count >= 2, elapsedDays > 0 {
            return ProjectionBasisCandidate(
                basis: .currentPeriod,
                averageDailyConsumption: max(currentConsumption / elapsedDays, 0),
                dayCount: elapsedDays,
                readings: currentPeriodReadings
            )
        }

        if let recent = recentReadingBasis(from: readings, referenceDate: referenceDate) {
            return recent
        }

        guard let first = readings.first,
              let last = readings.last,
              let historicalAverage = averageDailyConsumption(from: readings) else {
            return nil
        }

        return ProjectionBasisCandidate(
            basis: .historicalAverage,
            averageDailyConsumption: max(historicalAverage, 0),
            dayCount: max(last.recordedAt.timeIntervalSince(first.recordedAt) / 86_400, 0),
            readings: readings
        )
    }

    private static func recentReadingBasis(from readings: [MeterReading], referenceDate: Date) -> ProjectionBasisCandidate? {
        let recentReadings = Array(readings.suffix(min(4, readings.count)))
        guard let first = recentReadings.first,
              let last = recentReadings.last,
              recentReadings.count >= 2 else {
            return nil
        }

        let days = last.recordedAt.timeIntervalSince(first.recordedAt) / 86_400
        let latestReadingAgeDays = max(referenceDate.timeIntervalSince(last.recordedAt) / 86_400, 0)
        guard days > 0, latestReadingAgeDays <= 90 else { return nil }

        return ProjectionBasisCandidate(
            basis: .recentReadings,
            averageDailyConsumption: max((last.value - first.value) / days, 0),
            dayCount: days,
            readings: recentReadings
        )
    }

    private static func projectionQuality(
        readings: [MeterReading],
        basis: ProjectionBasis,
        referenceDate: Date
    ) -> ProjectionQuality {
        guard let latestReading = readings.last else { return .low }

        let latestReadingAgeDays = max(referenceDate.timeIntervalSince(latestReading.recordedAt) / 86_400, 0)
        let variability = dailyRateVariability(from: readings)

        if basis == .currentPeriod,
           readings.count >= 3,
           latestReadingAgeDays <= 7,
           variability <= 0.35 {
            return .high
        }

        if basis != .historicalAverage,
           readings.count >= 2,
           latestReadingAgeDays <= 21,
           variability <= 0.75 {
            return .medium
        }

        return .low
    }

    private static func dailyRateVariability(from readings: [MeterReading]) -> Double {
        let rates = zip(readings, readings.dropFirst()).compactMap { previous, current -> Double? in
            let days = current.recordedAt.timeIntervalSince(previous.recordedAt) / 86_400
            guard days > 0 else { return nil }
            return max(current.value - previous.value, 0) / days
        }
        guard rates.count >= 2 else { return 0 }

        let mean = rates.reduce(0, +) / Double(rates.count)
        guard mean > 0 else { return 0 }

        let variance = rates.reduce(0) { partialResult, rate in
            partialResult + pow(rate - mean, 2)
        } / Double(rates.count)
        return sqrt(variance) / mean
    }

    private static func recommendedReadingDate(
        for quality: ProjectionQuality,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let dayOffset: Int
        switch quality {
        case .high:
            dayOffset = 14
        case .medium:
            dayOffset = 7
        case .low:
            dayOffset = 0
        }

        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) ?? referenceDate)
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

    private static func dateIntervalRange(_ interval: DateInterval?, fallback: Date) -> (Date, Date) {
        let startsAt = interval?.start ?? fallback
        let endsAt = interval?.end.addingTimeInterval(-1) ?? fallback
        return (startsAt, endsAt)
    }

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))?.addingTimeInterval(-1) ?? date
    }

    private static func effectiveRange(_ range: StatisticsDateRange, referenceDate: Date) -> StatisticsDateRange {
        guard range.contains(referenceDate) else { return range }
        return StatisticsDateRange(startsAt: range.startsAt, endsAt: min(referenceDate, range.endsAt))
    }
}
