import AppKit
import Charts
import SwiftUI

struct MeterDetailView: View {
    let meter: Meter
    let readings: [MeterReading]
    let isBusy: Bool
    @Binding var statisticsPeriod: StatisticsPeriod
    @Binding var customStatisticsStartDate: Date
    @Binding var customStatisticsEndDate: Date
    let onAddReading: () -> Void
    let onEditReading: (MeterReading) -> Void
    let onDeleteReading: (MeterReading) -> Void

    private var presentation: MeterDetailPresentation {
        MeterDetailPresentationBuilder.make(
            meter: meter,
            readings: readings,
            period: statisticsPeriod,
            customStart: customStatisticsStartDate,
            customEnd: customStatisticsEndDate
        )
    }

    var body: some View {
        let presentation = presentation

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MeterHeaderView(meter: meter, readings: readings)

                StatisticsScopeView(
                    period: $statisticsPeriod,
                    customStartDate: $customStatisticsStartDate,
                    customEndDate: $customStatisticsEndDate
                )

                if readings.isEmpty {
                    EmptyStateView(
                        title: String(localized: meter.isVirtual ? "virtualMeter.empty.title" : "readings.empty.title"),
                        message: String(localized: meter.isVirtual ? "virtualMeter.empty.message" : "readings.empty.message"),
                        systemImage: meter.isVirtual ? "function" : "plus.rectangle.on.rectangle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    if meter.isVirtual, readings.contains(where: { $0.value < 0 }) {
                        Label(String(localized: "virtualMeter.negative.warning"), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    StatisticsSummaryView(
                        meter: meter,
                        statistics: presentation.statistics,
                        comparison: presentation.comparison
                    )

                    PeriodComparisonView(
                        meter: meter,
                        comparison: presentation.comparison,
                        unavailableReason: presentation.statistics?.comparisonUnavailableReason
                    )

                    UsageChartView(
                        meter: meter,
                        buckets: presentation.usageBuckets
                    )

                    if supportsForecast {
                        ForecastView(
                            meter: meter,
                            readings: MeterAnalytics.sortedReadingsAscending(readings),
                            forecast: presentation.forecast
                        )
                    }

                    if !presentation.anomalies.isEmpty {
                        AnomalySectionView(meter: meter, anomalies: presentation.anomalies)
                    }

                    ReadingHistoryView(
                        meter: meter,
                        readings: MeterAnalytics.sortedReadingsDescending(readings),
                        allowsEditing: !meter.isVirtual,
                        onEdit: onEditReading,
                        onDelete: onDeleteReading
                    )
                }
            }
            .padding(24)
        }
        .navigationTitle(meter.name)
        .toolbar {
            if !meter.isVirtual {
            ToolbarItem {
                Button(action: onAddReading) {
                    Label(String(localized: "reading.add"), systemImage: "plus")
                }
                .help(String(localized: "reading.add"))
                .disabled(isBusy)
            }
            }
        }
    }

    private var supportsForecast: Bool {
        switch statisticsPeriod {
        case .currentMonth, .currentYear, .custom:
            true
        case .previousMonths, .previousYearMonths, .lastTwelveMonths, .previousYears:
            false
        }
    }
}

struct MeterHeaderView: View {
    let meter: Meter
    let readings: [MeterReading]

    private var latestReading: MeterReading? {
        MeterAnalytics.sortedReadingsDescending(readings).first
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            header(axis: .horizontal)
            header(axis: .vertical)
        }
    }

    @ViewBuilder
    private func header(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

        layout {
            VStack(alignment: .leading, spacing: 8) {
                Label(meter.kind.localizedName, systemImage: meter.kind.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(meter.kind.tintColor)

                Text(meter.name)
                    .font(.largeTitle.weight(.bold))

                ViewThatFits(in: .horizontal) {
                    meterMetadata(axis: .horizontal)
                    meterMetadata(axis: .vertical)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !meter.note.isEmpty {
                    Text(meter.note)
                        .foregroundStyle(.secondary)
                }

                if let formula = meter.virtualFormulaDescription {
                    Label(formula, systemImage: "function")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if axis == .horizontal {
                Spacer(minLength: 16)
            }

            MeterCurrentReadingView(meter: meter, latestReading: latestReading)
        }
    }

    @ViewBuilder
    private func meterMetadata(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))

        layout {
            if !meter.location.isEmpty {
                Label(meter.location, systemImage: "mappin.and.ellipse")
            }
        }
    }
}

struct MeterCurrentReadingView: View {
    let meter: Meter
    let latestReading: MeterReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(latestReading == nil ? String(localized: "readings.empty.short") : String(localized: "reading.value"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let latestReading {
                Text(MeterFormatting.value(
                    latestReading.value,
                    unit: meter.unit,
                    precision: meter.decimalPrecision
                ))
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)

                Text(MeterFormatting.readingDate(latestReading))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 170, alignment: .leading)
        .padding(14)
        .meterSurface(tint: meter.kind.tintColor)
    }
}

struct StatisticsScopeView: View {
    @Binding var period: StatisticsPeriod
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "statistics.title"))
                    .font(.title2.weight(.semibold))

                Spacer()

                Menu {
                    Button(String(localized: "statistics.period.currentMonth")) { period = .currentMonth }
                    Button(String(localized: "statistics.period.currentYear")) { period = .currentYear }
                    Button(String(localized: "statistics.period.lastTwelveMonths")) { period = .lastTwelveMonths }
                    Button(String(localized: "statistics.period.custom")) { period = .custom }

                    Divider()

                    Button(String(localized: "statistics.period.previousMonths")) { period = .previousMonths }
                    Button(String(localized: "statistics.period.previousYearMonths")) { period = .previousYearMonths }
                    Button(String(localized: "statistics.period.previousYears")) { period = .previousYears }
                } label: {
                    Label(period.localizedName, systemImage: "calendar")
                }
                .menuStyle(.borderlessButton)
            }

            if period == .custom {
                ViewThatFits(in: .horizontal) {
                    customDatePickers(axis: .horizontal)
                    customDatePickers(axis: .vertical)
                }
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func customDatePickers(axis: Axis) -> some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))

        layout {
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
}

struct StatisticsSummaryView: View {
    let meter: Meter
    let statistics: MeterStatisticsResult?
    let comparison: MeterPeriodComparison?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            StatisticsMetricCard(
                title: String(localized: "statistics.consumption"),
                value: statistics.map { MeterFormatting.value($0.consumption, unit: meter.unit, precision: meter.decimalPrecision) } ?? String(localized: "notAvailable"),
                detail: statistics.map(summaryDetail),
                tint: meter.kind.tintColor
            )

            StatisticsMetricCard(
                title: String(localized: "statistics.previous"),
                value: comparison.map(comparisonValue) ?? String(localized: "notAvailable"),
                detail: comparison.map(comparisonDetail),
                tint: comparison.map { $0.absoluteDelta <= 0 ? .green : .orange } ?? .secondary
            )

            StatisticsMetricCard(
                title: String(localized: "insight.averageDaily"),
                value: statistics?.averageDailyConsumption.map {
                    "\(MeterFormatting.decimal($0, precision: meter.decimalPrecision)) \(meter.unit)/\(String(localized: "day.short"))"
                } ?? String(localized: "notAvailable"),
                detail: nil,
                tint: meter.kind.tintColor
            )

            StatisticsMetricCard(
                title: String(localized: "statistics.projectedEstimate"),
                value: statistics?.projectedConsumption.map {
                    MeterFormatting.value($0, unit: meter.unit, precision: meter.decimalPrecision)
                } ?? String(localized: "notAvailable"),
                detail: projectedDetail,
                tint: .orange
            )
        }
    }

    private var projectedDetail: String? {
        guard let statistics,
              let projectedCost = statistics.projectedCost,
              let tariff = meter.activeTariff else {
            return nil
        }
        return MeterFormatting.currency(projectedCost, currencyCode: tariff.currencyCode)
    }

    private func summaryDetail(_ statistics: MeterStatisticsResult) -> String {
        if statistics.ranges.count > 1 {
            return String(localized: "statistics.detail.multiplePeriods \(statistics.ranges.count)")
        }
        if statistics.ranges.contains(where: { $0.contains(Date()) }) {
            return String(localized: "statistics.detail.untilToday")
        }
        return String(localized: "statistics.detail.selectedRange")
    }

    private func comparisonValue(_ comparison: MeterPeriodComparison) -> String {
        if let percentageDelta = comparison.percentageDelta {
            return MeterFormatting.signedPercent(percentageDelta)
        }
        return MeterFormatting.value(
            abs(comparison.absoluteDelta),
            unit: meter.unit,
            precision: meter.decimalPrecision
        )
    }

    private func comparisonDetail(_ comparison: MeterPeriodComparison) -> String {
        let delta = MeterFormatting.value(
            abs(comparison.absoluteDelta),
            unit: meter.unit,
            precision: meter.decimalPrecision
        )
        let sign = comparison.absoluteDelta >= 0 ? "+" : "−"
        return "\(sign)\(delta)"
    }
}

struct StatisticsMetricCard: View {
    let title: String
    let value: String
    let detail: String?
    let tint: Color

    @ScaledMetric(relativeTo: .title2) private var cardHeight = 104.0
    @ScaledMetric(relativeTo: .caption) private var detailHeight = 14.0

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: detailHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .meterSurface(tint: tint)
    }
}

struct PeriodComparisonView: View {
    let meter: Meter
    let comparison: MeterPeriodComparison?
    let unavailableReason: StatisticsUnavailableReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "statistics.comparison.title"))
                .font(.headline)

            if let comparison {
                Chart {
                    BarMark(
                        x: .value(String(localized: "chart.period"), String(localized: "statistics.comparison.current")),
                        y: .value(String(localized: "chart.consumption"), comparison.currentConsumption)
                    )
                    .foregroundStyle(meter.kind.tintColor)

                    BarMark(
                        x: .value(String(localized: "chart.period"), String(localized: "statistics.comparison.previous")),
                        y: .value(String(localized: "chart.consumption"), comparison.previousConsumption)
                    )
                    .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .chartYAxisLabel(meter.unit)
                .accessibilityLabel(comparisonAccessibilitySummary(comparison))

                Text(String(localized: "statistics.comparison.detail \(rangeText(comparison.currentRange)) \(rangeText(comparison.previousRange))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(unavailableReason?.localizedText ?? String(localized: "notAvailable"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .padding(14)
        .meterSurface()
    }

    private func rangeText(_ range: StatisticsDateRange) -> String {
        "\(MeterFormatting.shortDate(range.startsAt)) – \(MeterFormatting.shortDate(range.endsAt))"
    }

    private func comparisonAccessibilitySummary(_ comparison: MeterPeriodComparison) -> String {
        String(localized: "statistics.comparison.accessibility \(MeterFormatting.value(comparison.currentConsumption, unit: meter.unit, precision: meter.decimalPrecision)) \(MeterFormatting.value(comparison.previousConsumption, unit: meter.unit, precision: meter.decimalPrecision))")
    }
}

struct UsageChartView: View {
    let meter: Meter
    let buckets: [UsageBucket]

    private var currentLabel: String { String(localized: "statistics.comparison.current") }
    private var previousLabel: String { String(localized: "statistics.comparison.previous") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "charts.usage.title"))
                .font(.headline)

            if buckets.isEmpty {
                Text(String(localized: "charts.selectedRange.empty"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        if let currentValue = bucket.currentValue {
                            BarMark(
                                x: .value(String(localized: "chart.period"), bucket.index),
                                y: .value(String(localized: "chart.consumption"), currentValue)
                            )
                            .foregroundStyle(meter.kind.tintColor)
                            .position(by: .value(String(localized: "chart.series"), currentLabel))
                        }

                        if let previousValue = bucket.previousValue {
                            BarMark(
                                x: .value(String(localized: "chart.period"), bucket.index),
                                y: .value(String(localized: "chart.consumption"), previousValue)
                            )
                            .foregroundStyle(.secondary.opacity(0.55))
                            .position(by: .value(String(localized: "chart.series"), previousLabel))
                        }
                    }
                }
                .frame(height: 230)
                .chartYAxisLabel(meter.unit)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let index = value.as(Int.self),
                               let bucket = buckets.first(where: { $0.index == index }) {
                                Text(MeterFormatting.shortDate(bucket.labelDate))
                            }
                        }
                    }
                }
                .accessibilityLabel(String(localized: "charts.usage.accessibility"))

                HStack(spacing: 14) {
                    LegendItem(label: currentLabel, color: meter.kind.tintColor)
                    LegendItem(label: previousLabel, color: .secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .meterSurface()
    }
}

struct LegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        Label(label, systemImage: "square.fill")
            .foregroundStyle(color)
    }
}

struct ForecastView: View {
    let meter: Meter
    let readings: [MeterReading]
    let forecast: ForecastResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "forecast.estimate.title"))
                .font(.headline)

            if let forecast {
                let actualReadings = readings.filter { $0.recordedAt <= forecast.anchorDate }
                Chart {
                    ForEach(actualReadings) { reading in
                        LineMark(
                            x: .value(String(localized: "chart.date"), reading.recordedAt),
                            y: .value(String(localized: "chart.reading"), reading.value)
                        )
                        .foregroundStyle(meter.kind.tintColor)
                    }

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
                .frame(height: 190)
                .chartYAxisLabel(meter.unit)
                .accessibilityLabel(String(localized: "charts.forecast.accessibility"))

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
            } else {
                Text(String(localized: "forecast.insufficient.message"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .meterSurface()
    }
}

struct ReadingHistoryView: View {
    let meter: Meter
    let readings: [MeterReading]
    let allowsEditing: Bool
    let onEdit: (MeterReading) -> Void
    let onDelete: (MeterReading) -> Void

    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    private func yearGroups(for filteredReadings: [MeterReading]) -> [ReadingYearGroup] {
        let grouped = Dictionary(grouping: filteredReadings) {
            Calendar.current.component(.year, from: $0.recordedAt)
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
                    .font(.headline)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "readings.search.prompt"), text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFieldFocused)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "readings.search.clear"))
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .meterSurface(cornerRadius: 8)
                .frame(maxWidth: 240)
            }
            .background {
                Button(String(localized: "readings.search.focus")) {
                    searchFieldFocused = true
                }
                .keyboardShortcut("f", modifiers: [.command])
                .hidden()
                .accessibilityHidden(true)
            }

            if filteredReadings.isEmpty {
                Text(String(localized: "readings.search.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .meterSurface()
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
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(MeterFormatting.value(reading.value, unit: meter.unit, precision: meter.decimalPrecision))
                                            .font(.headline.monospacedDigit())
                                        Spacer()
                                        Text(MeterFormatting.readingDate(reading))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !reading.note.isEmpty {
                                        Text(reading.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .onTapGesture(count: 2) {
                                if allowsEditing { onEdit(reading) }
                            }
                            .contextMenu {
                                if allowsEditing {
                                    Button(String(localized: "reading.edit")) { onEdit(reading) }
                                    Button(String(localized: "reading.delete"), role: .destructive) { onDelete(reading) }
                                    Divider()
                                }
                                Button(String(localized: "reading.copyValue")) { copyToPasteboard(valueText(for: reading)) }
                                Button(String(localized: "reading.copyDate")) { copyToPasteboard(MeterFormatting.readingDate(reading)) }
                                Button(String(localized: "reading.copySummary")) { copyToPasteboard(summaryText(for: reading)) }
                            }

                            if reading.id != group.readings.last?.id || group.id != yearGroups.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .meterSurface()
            }
        }
    }

    private func valueText(for reading: MeterReading) -> String {
        MeterFormatting.value(reading.value, unit: meter.unit, precision: meter.decimalPrecision)
    }

    private func summaryText(for reading: MeterReading) -> String {
        let base = String(localized: "reading.summary \(valueText(for: reading)) \(MeterFormatting.readingDate(reading))")
        guard !reading.note.isEmpty else { return base }
        return String(localized: "reading.summaryWithNote \(valueText(for: reading)) \(MeterFormatting.readingDate(reading)) \(reading.note)")
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct ReadingYearGroup: Identifiable {
    let year: Int
    let readings: [MeterReading]

    var id: Int { year }
    var title: String { "\(year)" }
}

struct AnomalySectionView: View {
    let meter: Meter
    let anomalies: [ConsumptionAnomaly]

    private static let maximumVisibleAnomalies = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "anomaly.title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(anomalies.suffix(Self.maximumVisibleAnomalies).reversed())) { anomaly in
                    Label {
                        Text(explanation(for: anomaly))
                    } icon: {
                        Image(systemName: iconName(for: anomaly.kind))
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
            }
            .meterSurface()
        }
    }

    private func iconName(for kind: ConsumptionAnomaly.Kind) -> String {
        switch kind {
        case .unusuallyHigh:
            "arrow.up.right.circle"
        case .unusuallyLow:
            "arrow.down.right.circle"
        case .decrease:
            "arrow.counterclockwise.circle"
        }
    }

    private func explanation(for anomaly: ConsumptionAnomaly) -> String {
        let range = "\(MeterFormatting.shortDate(anomaly.startDate)) – \(MeterFormatting.shortDate(anomaly.endDate))"
        switch anomaly.kind {
        case .unusuallyHigh:
            return String(localized: "anomaly.high \(range) \(MeterFormatting.decimal(anomaly.ratioToTypical))")
        case .unusuallyLow:
            return String(localized: "anomaly.low \(range)")
        case .decrease:
            return String(localized: "anomaly.decrease \(range)")
        }
    }
}
