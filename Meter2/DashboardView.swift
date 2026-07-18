import SwiftUI

struct DashboardView: View {
    let meters: [Meter]
    let addMeter: () -> Void
    let isAddMeterDisabled: Bool
    let selectMeter: (Meter) -> Void
    let meterCommands: (Meter) -> MeterContextCommands

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if meters.isEmpty {
                    VStack(spacing: 18) {
                        EmptyStateView(
                            title: String(localized: "dashboard.empty.title"),
                            message: String(localized: "dashboard.empty.message"),
                            systemImage: "plus.square.dashed"
                        )

                        Button {
                            addMeter()
                        } label: {
                            Label(String(localized: "meter.add"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isAddMeterDisabled)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    DashboardSummaryGrid(meters: meters)

                    Text(String(localized: "dashboard.meters.title"))
                        .font(.title2.weight(.semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(meters) { meter in
                            Button {
                                selectMeter(meter)
                            } label: {
                                MeterCardView(meter: meter, readings: MeterReadingResolver.readings(for: meter))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                MeterContextMenu(commands: meterCommands(meter))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(String(localized: "navigation.dashboard"))
    }
}

struct DashboardSummaryGrid: View {
    let meters: [Meter]

    var body: some View {
        let readingCount = meters.reduce(0) { $0 + MeterReadingResolver.readings(for: $1).count }
        let forecastCount = meters.filter { meter in
            let readings = MeterReadingResolver.readings(for: meter)
            let period = meter.activeBillingPeriod.map { ($0.startsAt, $0.endsAt) }
                ?? MeterAnalytics.defaultBillingPeriod(containing: Date())
            return MeterAnalytics.forecast(
                readings: readings,
                periodStart: period.0,
                periodEnd: period.1,
                tariff: meter.activeTariff
            ) != nil
        }.count

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                DashboardOverviewMetric(title: String(localized: "dashboard.activeMeters"), value: "\(meters.count)", systemImage: "list.bullet.rectangle")
                Divider().padding(.vertical, 10)
                DashboardOverviewMetric(title: String(localized: "dashboard.readings"), value: "\(readingCount)", systemImage: "number")
                Divider().padding(.vertical, 10)
                DashboardOverviewMetric(title: String(localized: "dashboard.forecasts"), value: "\(forecastCount)", systemImage: "chart.line.uptrend.xyaxis")
            }
            .meterSurface()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                DashboardOverviewMetric(title: String(localized: "dashboard.activeMeters"), value: "\(meters.count)", systemImage: "list.bullet.rectangle").meterSurface()
                DashboardOverviewMetric(title: String(localized: "dashboard.readings"), value: "\(readingCount)", systemImage: "number").meterSurface()
                DashboardOverviewMetric(title: String(localized: "dashboard.forecasts"), value: "\(forecastCount)", systemImage: "chart.line.uptrend.xyaxis").meterSurface()
            }
        }
    }
}

struct MeterCardView: View {
    let meter: Meter
    let readings: [MeterReading]

    private var latestReading: MeterReading? {
        MeterAnalytics.sortedReadingsDescending(readings).first
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: meter.kind.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(meter.kind.tintColor)
                .frame(width: 38, height: 38)
                .background(meter.kind.subtleTintColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(meter.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(meter.kind.localizedName)
                    if !meter.location.isEmpty {
                        Text("•")
                        Text(meter.location)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let latestReading {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(MeterFormatting.value(latestReading.value, unit: meter.unit, precision: meter.decimalPrecision))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                    Text(MeterFormatting.readingDate(latestReading))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "readings.empty.short"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .meterSurface(tint: meter.kind.tintColor)
    }
}

struct DashboardOverviewMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}
