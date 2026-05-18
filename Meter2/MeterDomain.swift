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
    case month
    case quarter
    case year
    case all

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .month:
            String(localized: "statistics.period.month")
        case .quarter:
            String(localized: "statistics.period.quarter")
        case .year:
            String(localized: "statistics.period.year")
        case .all:
            String(localized: "statistics.period.all")
        }
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
    case allHistory
    case previousPeriodNotCovered
    case notEnoughData

    var localizedText: String {
        switch self {
        case .allHistory:
            String(localized: "statistics.unavailable.allHistory")
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
        calendar: Calendar = .current
    ) -> (Date, Date)? {
        switch period {
        case .month:
            return dateIntervalRange(calendar.dateInterval(of: .month, for: date), fallback: date)
        case .quarter:
            let month = calendar.component(.month, from: date)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: date)
            components.month = quarterStartMonth
            components.day = 1
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: .month, value: 3, to: start)?.addingTimeInterval(-1) else {
                return nil
            }
            return (start, end)
        case .year:
            return dateIntervalRange(calendar.dateInterval(of: .year, for: date), fallback: date)
        case .all:
            let sortedReadings = sortedReadingsAscending(readings)
            guard let first = sortedReadings.first, let last = sortedReadings.last else { return nil }
            return (first.recordedAt, last.recordedAt)
        }
    }

    static func previousStatisticsPeriodRange(
        for period: StatisticsPeriod,
        currentStart: Date,
        currentEnd: Date,
        calendar: Calendar = .current
    ) -> (Date, Date)? {
        switch period {
        case .month:
            guard let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart),
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousStart, previousEnd)
        case .quarter:
            guard let previousStart = calendar.date(byAdding: .month, value: -3, to: currentStart),
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousStart, previousEnd)
        case .year:
            guard let previousStart = calendar.date(byAdding: .year, value: -1, to: currentStart),
                  let previousEnd = calendar.date(byAdding: .second, value: -1, to: currentStart) else { return nil }
            return (previousStart, previousEnd)
        case .all:
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
        calendar: Calendar = .current
    ) -> MeterStatisticsResult? {
        let sortedReadings = sortedReadingsAscending(readings)
        guard sortedReadings.count >= 2,
              let range = statisticsPeriodRange(period, containing: referenceDate, readings: sortedReadings, calendar: calendar) else {
            return nil
        }

        let now = min(max(referenceDate, range.0), range.1)
        let consumptionEnd = period == .all ? range.1 : now
        guard let consumption = consumption(from: sortedReadings, periodStart: range.0, periodEnd: consumptionEnd) else {
            return nil
        }

        let elapsedDays = max(consumptionEnd.timeIntervalSince(range.0) / 86_400, 0)
        let averageDailyConsumption = elapsedDays > 0 ? consumption / elapsedDays : nil
        let projection = period == .all ? nil : projection(
            readings: sortedReadings,
            periodStart: range.0,
            periodEnd: range.1,
            referenceDate: referenceDate,
            tariff: tariff,
            calendar: calendar
        )
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

            let absoluteDelta = consumption - previousConsumption
            let percentageDelta = previousConsumption > 0 ? absoluteDelta / previousConsumption : nil
            return MeterPeriodComparison(
                currentConsumption: consumption,
                previousConsumption: previousConsumption,
                absoluteDelta: absoluteDelta,
                percentageDelta: percentageDelta
            )
        }
        if comparisonRange == nil {
            comparisonUnavailableReason = .allHistory
        }

        return MeterStatisticsResult(
            period: period,
            startsAt: range.0,
            endsAt: range.1,
            consumption: consumption,
            averageDailyConsumption: averageDailyConsumption,
            lastConsumptionPace: lastConsumptionPace(from: sortedReadings),
            projectedConsumption: projection?.projectedConsumption,
            projectedCost: projection?.projectedCost,
            projectionBasis: projection?.basis,
            projectionQuality: projection?.quality,
            projectionBasisDayCount: projection?.basisDayCount,
            projectionBasisReadingCount: projection?.basisReadingCount,
            nextRecommendedReadingDate: projection?.nextRecommendedReadingDate,
            comparison: comparison,
            comparisonUnavailableReason: comparison == nil ? comparisonUnavailableReason : nil
        )
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
}
