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
                                MeterCardView(meter: meter)
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
        let readingCount = meters.reduce(0) { $0 + $1.readings.count }
        let forecastCount = meters.filter { meter in
            let period = meter.activeBillingPeriod.map { ($0.startsAt, $0.endsAt) }
                ?? MeterAnalytics.defaultBillingPeriod(containing: Date())
            return MeterAnalytics.forecast(
                readings: meter.readings,
                periodStart: period.0,
                periodEnd: period.1,
                tariff: meter.activeTariff
            ) != nil
        }.count

        HStack(spacing: 12) {
            InsightCard(title: String(localized: "dashboard.activeMeters"), value: "\(meters.count)", systemImage: "list.bullet.rectangle")
            InsightCard(title: String(localized: "dashboard.readings"), value: "\(readingCount)", systemImage: "number")
            InsightCard(title: String(localized: "dashboard.forecasts"), value: "\(forecastCount)", systemImage: "chart.line.uptrend.xyaxis")
        }
    }
}

struct MeterCardView: View {
    let meter: Meter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(meter.kind.localizedName, systemImage: meter.kind.symbolName)
                    .font(.headline)
                    .foregroundStyle(meter.kind.tintColor)
                Spacer()
                if meter.isArchived {
                    Text(String(localized: "meter.archived"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(meter.name)
                .font(.title3.weight(.semibold))

            if let latestReading = meter.latestReading {
                Text(MeterFormatting.value(latestReading.value, unit: meter.unit, precision: meter.decimalPrecision))
                    .font(.title2.monospacedDigit())
                Text(MeterFormatting.readingDate(latestReading))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "readings.empty.short"))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(meter.kind.subtleTintColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(meter.kind.subtleStrokeColor, lineWidth: 1)
        )
    }
}
