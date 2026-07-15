import XCTest

@testable import Meter2

final class MeterAnalyticsTests: XCTestCase {
    func testVirtualMeterCalculatesSolarSelfConsumption() throws {
        let calendar = utcCalendar()
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let production = meter(name: "Production", values: [(start, 100), (end, 160)])
        let feedIn = meter(name: "Feed-in", values: [(start, 30), (end, 50)])
        let virtual = virtualMeter(terms: [(.add, production), (.subtract, feedIn)])

        let readings = MeterReadingResolver.readings(for: virtual)

        XCTAssertEqual(readings.map(\.value), [70, 110])
        XCTAssertEqual(MeterAnalytics.consumptionDeltas(from: readings).map(\.value), [40])
    }

    func testVirtualMeterInterpolatesStaggeredSourceReadingsInsideSharedCoverage() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let middle = start.addingTimeInterval(86_400)
        let end = start.addingTimeInterval(172_800)
        let production = meter(name: "Production", values: [(start, 100), (end, 200)])
        let feedIn = meter(name: "Feed-in", values: [(middle, 20), (end, 40)])
        let virtual = virtualMeter(terms: [(.add, production), (.subtract, feedIn)])

        let readings = MeterReadingResolver.readings(for: virtual)

        XCTAssertEqual(readings.map(\.recordedAt), [middle, end])
        XCTAssertEqual(readings.map(\.value), [130, 160])
    }

    func testVirtualMeterDoesNotExtrapolateOrResolveVirtualSources() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let middle = start.addingTimeInterval(86_400)
        let end = start.addingTimeInterval(172_800)
        let first = meter(name: "First", values: [(start, 10), (middle, 20)])
        let second = meter(name: "Second", values: [(end, 30), (end.addingTimeInterval(86_400), 40)])
        let noOverlap = virtualMeter(terms: [(.add, first), (.add, second)])
        XCTAssertTrue(MeterReadingResolver.readings(for: noOverlap).isEmpty)

        first.dataSourceKind = .virtual
        let virtualSource = virtualMeter(terms: [(.add, first)])
        XCTAssertTrue(MeterReadingResolver.readings(for: virtualSource).isEmpty)

        first.dataSourceKind = .manual
        first.unit = "L"
        let mismatchedUnit = virtualMeter(terms: [(.add, first)])
        XCTAssertTrue(MeterReadingResolver.readings(for: mismatchedUnit).isEmpty)
    }

    func testVirtualMeterDerivedReadingIDsAreStable() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(86_400)
        let source = meter(name: "Source", values: [(start, 10), (end, 20)])
        let virtual = virtualMeter(terms: [(.add, source)])

        XCTAssertEqual(
            MeterReadingResolver.readings(for: virtual).map(\.id),
            MeterReadingResolver.readings(for: virtual).map(\.id)
        )
    }

    func testVirtualMeterCoalescesMixedGranularityAndDisplayedMinuteTimestamps() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let sourceA = Meter(name: "Daily", kind: .electricity, unit: "kWh")
        sourceA.readings = [
            MeterReading(value: 10, recordedAt: day, recordedAtGranularity: .dateOnly),
            MeterReading(value: 20, recordedAt: nextDay, recordedAtGranularity: .dateOnly)
        ]
        let sourceB = Meter(name: "Timed", kind: .electricity, unit: "kWh")
        sourceB.readings = [
            MeterReading(value: 2, recordedAt: day.addingTimeInterval(10), recordedAtGranularity: .dateTime),
            MeterReading(value: 3, recordedAt: day.addingTimeInterval(40), recordedAtGranularity: .dateTime),
            MeterReading(value: 4, recordedAt: nextDay, recordedAtGranularity: .dateTime)
        ]

        let readings = MeterReadingResolver.readings(for: virtualMeter(terms: [(.add, sourceA), (.subtract, sourceB)]))

        XCTAssertEqual(readings.count, 2)
        XCTAssertEqual(readings.map(\.recordedAt), [day.addingTimeInterval(10), nextDay])
        XCTAssertTrue(readings.allSatisfy { $0.recordedAtGranularity == .dateTime })
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
        XCTAssertEqual(comparison.previousConsumption, 7, accuracy: 0.01)
        XCTAssertEqual(comparison.absoluteDelta, 63, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(comparison.percentageDelta), 9, accuracy: 0.01)
        XCTAssertEqual(comparison.currentRange.startsAt, calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        XCTAssertEqual(comparison.currentRange.endsAt, reference)
        XCTAssertEqual(comparison.previousRange.startsAt, calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        XCTAssertEqual(comparison.previousRange.endsAt, calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 0))!)
    }

    func testLastTwelveMonthsComparesAgainstThePriorTwelveMonths() throws {
        let calendar = utcCalendar()
        let readings = [
            MeterReading(value: 0, recordedAt: calendar.date(from: DateComponents(year: 2024, month: 8, day: 1))!),
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2025, month: 8, day: 1))!),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 7, day: 9))!)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 12))!

        let statistics = try XCTUnwrap(MeterAnalytics.statistics(
            for: readings,
            period: .lastTwelveMonths,
            referenceDate: reference,
            calendar: calendar
        ))
        let comparison = try XCTUnwrap(statistics.comparison)

        XCTAssertEqual(comparison.currentRange.startsAt, calendar.date(from: DateComponents(year: 2025, month: 8, day: 1)))
        XCTAssertEqual(comparison.previousRange.startsAt, calendar.date(from: DateComponents(year: 2024, month: 8, day: 1)))
        XCTAssertEqual(comparison.previousRange.endsAt, calendar.date(from: DateComponents(year: 2025, month: 7, day: 9, hour: 12)))
    }

    func testMeterDetailPresentationBuildsAlignedUsageBuckets() throws {
        let calendar = utcCalendar()
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings = [
            MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!, meter: meter),
            MeterReading(value: 130, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!, meter: meter),
            MeterReading(value: 200, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))!, meter: meter)
        ]
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12))!

        let presentation = MeterDetailPresentationBuilder.make(
            meter: meter,
            period: .currentMonth,
            customStart: reference,
            customEnd: reference,
            referenceDate: reference,
            calendar: calendar
        )

        XCTAssertNotNil(presentation.comparison)
        XCTAssertGreaterThanOrEqual(presentation.usageBuckets.count, 8)
        XCTAssertEqual(presentation.usageBuckets.first?.index, 0)
        XCTAssertEqual(presentation.usageBuckets.last?.index, presentation.usageBuckets.count - 1)
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

    private func dailyReadings(deltas: [Double]) -> [MeterReading] {
        var value = 1000.0
        var readings = [MeterReading(value: value, recordedAt: Date(timeIntervalSinceReferenceDate: 0))]
        for (index, delta) in deltas.enumerated() {
            value += delta
            readings.append(
                MeterReading(value: value, recordedAt: Date(timeIntervalSinceReferenceDate: Double(index + 1) * 86_400))
            )
        }
        return readings
    }

    func testConsumptionAnomaliesFlagUnusuallyHighSegmentAgainstMedian() {
        let readings = dailyReadings(deltas: [10, 10, 10, 40, 10, 10])

        let anomalies = MeterAnalytics.consumptionAnomalies(from: readings)

        XCTAssertEqual(anomalies.count, 1)
        XCTAssertEqual(anomalies.first?.kind, .unusuallyHigh)
        XCTAssertEqual(anomalies.first?.dailyRate ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(anomalies.first?.typicalDailyRate ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(anomalies.first?.ratioToTypical ?? 0, 4, accuracy: 0.001)
    }

    func testConsumptionAnomaliesFlagLowAndDecreasingSegments() {
        let readings = dailyReadings(deltas: [10, 10, 1, 10, -100, 10])

        let anomalies = MeterAnalytics.consumptionAnomalies(from: readings)

        XCTAssertEqual(anomalies.map(\.kind), [.unusuallyLow, .decrease])
    }

    func testConsumptionAnomaliesUseOddSegmentCountMedian() {
        let readings = dailyReadings(deltas: [10, 12, 10, 40, 10])

        let anomalies = MeterAnalytics.consumptionAnomalies(from: readings)

        XCTAssertEqual(anomalies.count, 1)
        XCTAssertEqual(anomalies.first?.kind, .unusuallyHigh)
        XCTAssertEqual(anomalies.first?.typicalDailyRate ?? 0, 10, accuracy: 0.001)
    }

    func testConsumptionAnomaliesAreEmptyForStableUsage() {
        let readings = dailyReadings(deltas: [10, 11, 9, 10, 12, 10])

        XCTAssertTrue(MeterAnalytics.consumptionAnomalies(from: readings).isEmpty)
    }

    func testConsumptionAnomaliesRequireMinimumSegments() {
        let readings = dailyReadings(deltas: [10, 10, 40, 10])

        XCTAssertTrue(MeterAnalytics.consumptionAnomalies(from: readings).isEmpty)
    }

    func testConsumptionAnomaliesAreEmptyWithoutPositiveMedian() {
        let readings = dailyReadings(deltas: [0, 0, 0, 0, 5, 0])

        XCTAssertTrue(MeterAnalytics.consumptionAnomalies(from: readings).isEmpty)
    }

    private func meter(name: String, values: [(Date, Double)]) -> Meter {
        let meter = Meter(name: name, kind: .electricity, unit: "kWh")
        meter.readings = values.map {
            MeterReading(value: $0.1, recordedAt: $0.0, recordedAtGranularity: .dateOnly, meter: meter)
        }
        return meter
    }

    private func virtualMeter(terms: [(VirtualMeterOperation, Meter)]) -> Meter {
        let meter = Meter(name: "Virtual", kind: .electricity, unit: "kWh")
        meter.dataSourceKind = .virtual
        meter.virtualTerms = terms.enumerated().map { index, pair in
            VirtualMeterTerm(operation: pair.0, displayOrder: index, owner: meter, source: pair.1)
        }
        return meter
    }
}
