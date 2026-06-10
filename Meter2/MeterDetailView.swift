import Charts
import SwiftUI

struct MeterDetailView: View {
    let meter: Meter
    let isBusy: Bool
    @Binding var statisticsPeriod: StatisticsPeriod
    @Binding var customStatisticsStartDate: Date
    @Binding var customStatisticsEndDate: Date
    let onAddReading: () -> Void
    let onEditMeter: () -> Void
    let onDeleteMeter: () -> Void
    let onEditReading: (MeterReading) -> Void
    let onDeleteReading: (MeterReading) -> Void
    let canManageMeter: Bool
    let canDeleteReadings: Bool

    private var readingsAscending: [MeterReading] {
        meter.sortedReadingsAscending
    }

    private var scopedReadingsAscending: [MeterReading] {
        MeterAnalytics.readings(readingsAscending, in: statisticsRanges)
    }

    private var readingsDescending: [MeterReading] {
        meter.sortedReadingsDescending
    }

    private var scopedDeltas: [ConsumptionDelta] {
        MeterAnalytics.scopedConsumptionDeltas(from: meter.readings, in: statisticsRanges)
    }

    private var statisticsRanges: [StatisticsDateRange] {
        MeterAnalytics.statisticsPeriodRanges(
            statisticsPeriod,
            containing: Date(),
            readings: meter.readings,
            customStart: customStatisticsStartDate,
            customEnd: customStatisticsEndDate
        )
    }

    private var forecast: ForecastResult? {
        let ranges = statisticsRanges
        guard ranges.count == 1, let range = ranges.first, range.contains(Date()) else {
            return nil
        }

        return MeterAnalytics.forecast(
            readings: meter.readings,
            periodStart: range.startsAt,
            periodEnd: range.endsAt,
            tariff: meter.activeTariff
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MeterHeaderView(meter: meter)

                MeterInsightGrid(
                    meter: meter,
                    period: $statisticsPeriod,
                    customStartDate: $customStatisticsStartDate,
                    customEndDate: $customStatisticsEndDate
                )

                if readingsAscending.isEmpty {
                    EmptyStateView(
                        title: String(localized: "readings.empty.title"),
                        message: String(localized: "readings.empty.message"),
                        systemImage: "plus.rectangle.on.rectangle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ChartSectionView(
                        meter: meter,
                        readings: scopedReadingsAscending,
                        deltas: scopedDeltas,
                        forecast: forecast
                    )

                    ReadingHistoryView(
                        meter: meter,
                        readings: readingsDescending,
                        onEdit: onEditReading,
                        onDelete: onDeleteReading,
                        canDeleteReadings: canDeleteReadings
                    )
                }
            }
            .padding(24)
        }
        .navigationTitle(meter.name)
        .toolbar {
            ToolbarItemGroup {
                Button(action: onAddReading) {
                    Label(String(localized: "reading.add"), systemImage: "plus")
                }
                .help(String(localized: "reading.add"))
                .disabled(isBusy)

                Button(action: onEditMeter) {
                    Label(String(localized: "meter.edit"), systemImage: "slider.horizontal.3")
                }
                .help(String(localized: "meter.edit"))
                .disabled(isBusy || !canManageMeter)

                Button(role: .destructive, action: onDeleteMeter) {
                    Label(String(localized: "meter.delete"), systemImage: "trash")
                }
                .help(String(localized: "meter.delete"))
                .disabled(isBusy || !canManageMeter)
            }
        }
    }
}

struct MeterHeaderView: View {
    let meter: Meter

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Label(meter.kind.localizedName, systemImage: meter.kind.symbolName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(meter.name)
                    .font(.largeTitle.weight(.semibold))

                if !meter.location.isEmpty {
                    Label(meter.location, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                }

                if !meter.note.isEmpty {
                    Text(meter.note)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }
}

struct MeterInsightGrid: View {
    let meter: Meter
    @Binding var period: StatisticsPeriod
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "statistics.title"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker(String(localized: "statistics.period"), selection: $period) {
                    ForEach(StatisticsPeriod.allCases) { period in
                        Text(period.localizedName).tag(period)
                    }
                }
                .frame(width: 220)
            }

            if period == .custom {
                HStack {
                    DatePicker(
                        String(localized: "statistics.custom.start"),
                        selection: $customStartDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        String(localized: "statistics.custom.end"),
                        selection: $customEndDate,
                        displayedComponents: .date
                    )
                }
                .datePickerStyle(.compact)
            }

            let statistics = MeterAnalytics.statistics(
                for: meter.readings,
                period: period,
                tariff: meter.activeTariff,
                customStart: customStartDate,
                customEnd: customEndDate
            )
            let overviews = MeterAnalytics.periodOverviews(
                for: meter.readings,
                ranges: statistics?.ranges ?? [],
                referenceDate: Date()
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                InsightCard(
                    title: String(localized: "statistics.consumption"),
                    value: statistics.map { MeterFormatting.value($0.consumption, unit: meter.unit, precision: meter.decimalPrecision) } ?? String(localized: "notAvailable"),
                    detail: statistics.map { consumptionDetail(for: $0) },
                    systemImage: "sum"
                )
                InsightCard(
                    title: String(localized: "insight.averageDaily"),
                    value: statistics?.averageDailyConsumption.map { "\(MeterFormatting.decimal($0, precision: meter.decimalPrecision)) \(meter.unit)/\(String(localized: "day.short"))" } ?? String(localized: "notAvailable"),
                    detail: statistics?.projectionBasis.map { String(localized: "projection.basis.detail \($0.localizedName)") },
                    systemImage: "calendar"
                )
                InsightCard(
                    title: String(localized: "statistics.projectedEstimate"),
                    value: statistics?.projectedConsumption.map { MeterFormatting.value($0, unit: meter.unit, precision: meter.decimalPrecision) }
                        ?? String(localized: "notAvailable"),
                    detail: projectionDetail(for: statistics),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                InsightCard(
                    title: String(localized: "statistics.estimatedCost"),
                    value: statistics?.projectedCost.map { MeterFormatting.currency($0, currencyCode: meter.activeTariff?.currencyCode ?? Locale.current.currency?.identifier ?? "EUR") } ?? String(localized: "notAvailable"),
                    detail: meter.activeTariff == nil ? String(localized: "statistics.cost.noTariff") : nil,
                    systemImage: "creditcard"
                )
                InsightCard(
                    title: String(localized: "statistics.lastSegment"),
                    value: statistics?.lastConsumptionPace.map { MeterFormatting.value($0.consumption, unit: meter.unit, precision: meter.decimalPrecision) } ?? String(localized: "notAvailable"),
                    detail: statistics?.lastConsumptionPace.map { "\(MeterFormatting.decimal($0.averageDailyConsumption, precision: meter.decimalPrecision)) \(meter.unit)/\(String(localized: "day.short"))" },
                    systemImage: "arrow.forward.to.line"
                )
                InsightCard(
                    title: String(localized: "projection.quality"),
                    value: statistics?.projectionQuality?.localizedName ?? String(localized: "notAvailable"),
                    detail: statistics?.nextRecommendedReadingDate.map { String(localized: "statistics.nextReading \(MeterFormatting.shortDate($0))") },
                    systemImage: "gauge.with.dots.needle.67percent"
                )
                InsightCard(
                    title: String(localized: "statistics.previous"),
                    value: statistics?.comparison.map { comparisonText($0) } ?? String(localized: "notAvailable"),
                    detail: statistics?.comparison == nil ? statistics?.comparisonUnavailableReason?.localizedText : nil,
                    systemImage: "arrow.left.arrow.right"
                )
            }

            if !overviews.isEmpty {
                PeriodOverviewGrid(
                    meter: meter,
                    overviews: overviews
                )
            }
        }
    }

    private func consumptionDetail(for statistics: MeterStatisticsResult) -> String {
        if statistics.ranges.count > 1 {
            return String(localized: "statistics.detail.multiplePeriods \(statistics.ranges.count)")
        }
        if statistics.ranges.contains(where: { $0.contains(Date()) }) {
            return String(localized: "statistics.detail.untilToday")
        }
        return String(localized: "statistics.detail.selectedRange")
    }

    private func projectionDetail(for statistics: MeterStatisticsResult?) -> String? {
        guard let statistics,
              let basis = statistics.projectionBasis,
              let dayCount = statistics.projectionBasisDayCount,
              let readingCount = statistics.projectionBasisReadingCount else {
            return nil
        }

        return String(localized: "projection.detail \(basis.localizedName) \(Int(dayCount.rounded())) \(readingCount)")
    }

    private func comparisonText(_ comparison: MeterPeriodComparison) -> String {
        let value = MeterFormatting.value(abs(comparison.absoluteDelta), unit: meter.unit, precision: meter.decimalPrecision)
        let sign = comparison.absoluteDelta >= 0 ? "+" : "-"
        guard let percentageDelta = comparison.percentageDelta else {
            return "\(sign)\(value)"
        }

        return "\(sign)\(value) (\(MeterFormatting.signedPercent(percentageDelta)))"
    }
}

struct PeriodOverviewGrid: View {
    let meter: Meter
    let overviews: [StatisticsPeriodOverview]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "statistics.aggregation.title"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(overviews, id: \.granularity) { overview in
                    InsightCard(
                        title: overview.granularity.localizedName,
                        value: MeterFormatting.value(overview.averageConsumption, unit: meter.unit, precision: meter.decimalPrecision),
                        detail: String(localized: "statistics.aggregation.detail \(overview.periodCount) \(MeterFormatting.value(overview.totalConsumption, unit: meter.unit, precision: meter.decimalPrecision))"),
                        systemImage: systemImage(for: overview.granularity)
                    )
                }
            }
        }
    }

    private func systemImage(for granularity: StatisticsAggregationGranularity) -> String {
        switch granularity {
        case .week:
            "calendar.badge.clock"
        case .month:
            "calendar"
        case .year:
            "calendar.badge.exclamationmark"
        }
    }
}

struct InsightCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ChartSectionView: View {
    let meter: Meter
    let readings: [MeterReading]
    let deltas: [ConsumptionDelta]
    let forecast: ForecastResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "charts.title"))
                .font(.title2.weight(.semibold))

            if readings.isEmpty {
                Text(String(localized: "charts.selectedRange.empty"))
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(readings) { reading in
                        LineMark(
                            x: .value(String(localized: "chart.date"), reading.recordedAt),
                            y: .value(String(localized: "chart.reading"), reading.value)
                        )
                        .foregroundStyle(.blue)
                        PointMark(
                            x: .value(String(localized: "chart.date"), reading.recordedAt),
                            y: .value(String(localized: "chart.reading"), reading.value)
                        )
                        .foregroundStyle(.blue)
                    }

                    if let forecast {
                        LineMark(
                            x: .value(String(localized: "chart.date"), forecast.anchorDate),
                            y: .value(String(localized: "chart.forecast"), forecast.currentValue)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))

                        LineMark(
                            x: .value(String(localized: "chart.date"), forecast.endsAt),
                            y: .value(String(localized: "chart.forecast"), forecast.projectedValue)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                .frame(height: 240)
                .chartYAxisLabel(meter.unit)
                .accessibilityLabel(readingChartSummary)
                Text(readingChartSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if deltas.isEmpty {
                Text(String(localized: "charts.consumption.insufficient"))
                    .foregroundStyle(.secondary)
            } else {
                Chart(deltas) { delta in
                    BarMark(
                        x: .value(String(localized: "chart.date"), delta.endDate),
                        y: .value(String(localized: "chart.consumption"), delta.value)
                    )
                    .foregroundStyle(.green)
                }
                .frame(height: 180)
                .chartYAxisLabel(meter.unit)
                .accessibilityLabel(consumptionChartSummary)
                Text(consumptionChartSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForecastExplanationView(meter: meter, forecast: forecast)
        }
    }

    private var readingChartSummary: String {
        guard let first = readings.first, let latest = readings.last else {
            return String(localized: "accessibility.reading.chart")
        }

        return String(localized: "charts.reading.summary \(readings.count) \(MeterFormatting.value(first.value, unit: meter.unit, precision: meter.decimalPrecision)) \(MeterFormatting.readingDate(first)) \(MeterFormatting.value(latest.value, unit: meter.unit, precision: meter.decimalPrecision)) \(MeterFormatting.readingDate(latest))")
    }

    private var consumptionChartSummary: String {
        let total = deltas.reduce(0) { $0 + $1.value }
        return String(localized: "charts.consumption.summary \(deltas.count) \(MeterFormatting.value(total, unit: meter.unit, precision: meter.decimalPrecision))")
    }
}

struct ForecastExplanationView: View {
    let meter: Meter
    let forecast: ForecastResult?

    var body: some View {
        if let forecast {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "forecast.estimate.title"))
                    .font(.headline)
                Text(String(localized: "forecast.explanation \(MeterFormatting.value(forecast.projectedConsumption, unit: meter.unit, precision: meter.decimalPrecision)) \(MeterFormatting.shortDate(forecast.endsAt)) \(forecast.basis.localizedName) \(Int(forecast.basisDayCount.rounded())) \(forecast.basisReadingCount) \(forecast.quality.localizedName)"))
                    .foregroundStyle(.secondary)

                if let projectedCost = forecast.projectedCost, let tariff = meter.activeTariff {
                    Text(String(localized: "forecast.estimatedCost \(MeterFormatting.currency(projectedCost, currencyCode: tariff.currencyCode))"))
                        .foregroundStyle(.secondary)
                }

                if let nextReadingDate = forecast.nextRecommendedReadingDate {
                    Text(String(localized: "statistics.nextReading \(MeterFormatting.shortDate(nextReadingDate))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        } else {
            EmptyStateView(
                title: String(localized: "forecast.insufficient.title"),
                message: String(localized: "forecast.insufficient.message"),
                systemImage: "chart.line.uptrend.xyaxis"
            )
        }
    }
}

struct ReadingHistoryView: View {
    let meter: Meter
    let readings: [MeterReading]
    let onEdit: (MeterReading) -> Void
    let onDelete: (MeterReading) -> Void
    let canDeleteReadings: Bool

    @State private var searchText = ""

    private func yearGroups(for filteredReadings: [MeterReading]) -> [ReadingYearGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredReadings) {
            calendar.component(.year, from: $0.recordedAt)
        }
        return grouped.keys.sorted(by: >).map { year in
            ReadingYearGroup(year: year, readings: grouped[year] ?? [])
        }
    }

    var body: some View {
        let filteredReadings = ReadingSearch.filter(
            readings,
            query: searchText,
            unit: meter.unit,
            precision: meter.decimalPrecision
        )
        let yearGroups = yearGroups(for: filteredReadings)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "readings.history"))
                    .font(.title2.weight(.semibold))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "readings.search.prompt"), text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "readings.search.clear"))
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 240)
            }

            if filteredReadings.isEmpty {
                Text(String(localized: "readings.search.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(yearGroups) { group in
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(group.readings) { reading in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(MeterFormatting.value(reading.value, unit: meter.unit, precision: meter.decimalPrecision))
                                        .font(.headline.monospacedDigit())
                                    Text(MeterFormatting.readingDate(reading))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !reading.note.isEmpty {
                                        Text(reading.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button {
                                    onEdit(reading)
                                } label: {
                                    Label(String(localized: "edit"), systemImage: "pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help(String(localized: "reading.edit"))

                                Button(role: .destructive) {
                                    onDelete(reading)
                                } label: {
                                    Label(String(localized: "delete"), systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help(String(localized: "reading.delete"))
                                .disabled(!canDeleteReadings)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)

                            if reading.id != group.readings.last?.id || group.id != yearGroups.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct ReadingYearGroup: Identifiable {
    let year: Int
    let readings: [MeterReading]

    var id: Int { year }
    var title: String { "\(year)" }
}
