import Charts
import SwiftData
import SwiftUI

enum SidebarSelection: Hashable {
    case dashboard
    case meter(UUID)
}

enum ActiveSheet: Identifiable {
    case addMeter
    case editMeter(Meter)
    case addReading(Meter)
    case editReading(MeterReading)

    var id: String {
        switch self {
        case .addMeter:
            "add-meter"
        case .editMeter(let meter):
            "edit-meter-\(meter.id)"
        case .addReading(let meter):
            "add-reading-\(meter.id)"
        case .editReading(let reading):
            "edit-reading-\(reading.id)"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .system:
            String(localized: "appearance.system")
        case .light:
            String(localized: "appearance.light")
        case .dark:
            String(localized: "appearance.dark")
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func mode(for rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? .system
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meter.name) private var meters: [Meter]

    @AppStorage("appearanceMode") private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @State private var selection: SidebarSelection = .dashboard
    @State private var activeSheet: ActiveSheet?
    @State private var deletionCandidate: Meter?

    private var activeMeters: [Meter] {
        meters.filter { !$0.isArchived }
    }

    private var archivedMeters: [Meter] {
        meters.filter(\.isArchived)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.mode(for: appearanceModeRawValue)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(String(localized: "navigation.dashboard"), systemImage: "chart.xyaxis.line")
                    .tag(SidebarSelection.dashboard)

                Section(String(localized: "navigation.meters")) {
                    if activeMeters.isEmpty {
                        Text(String(localized: "meters.empty.sidebar"))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(activeMeters) { meter in
                        MeterSidebarRow(meter: meter)
                            .tag(SidebarSelection.meter(meter.id))
                    }
                }

                if !archivedMeters.isEmpty {
                    Section(String(localized: "navigation.archived")) {
                        ForEach(archivedMeters) { meter in
                            MeterSidebarRow(meter: meter)
                                .tag(SidebarSelection.meter(meter.id))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "app.name"))
            .toolbar {
                ToolbarItem {
                    Button {
                        activeSheet = .addMeter
                    } label: {
                        Label(String(localized: "meter.add"), systemImage: "plus")
                    }
                    .help(String(localized: "meter.add"))
                }
                ToolbarItem {
                    AppearanceModeMenu(selection: $appearanceModeRawValue, currentMode: appearanceMode)
                }
            }
        } detail: {
            detailView
        }
        .frame(
            minWidth: AppConfiguration.defaultWindowWidth,
            minHeight: AppConfiguration.defaultWindowHeight
        )
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addMeter:
                MeterFormView(mode: .add) { draft in
                    createMeter(from: draft)
                }
            case .editMeter(let meter):
                MeterFormView(mode: .edit(meter)) { draft in
                    update(meter, from: draft)
                }
            case .addReading(let meter):
                ReadingFormView(mode: .add(meter)) { draft in
                    createReading(for: meter, from: draft)
                }
            case .editReading(let reading):
                ReadingFormView(mode: .edit(reading)) { draft in
                    update(reading, from: draft)
                }
            }
        }
        .confirmationDialog(
            String(localized: "meter.delete.confirm.title"),
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            presenting: deletionCandidate
        ) { meter in
            Button(String(localized: "delete"), role: .destructive) {
                delete(meter)
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: { meter in
            Text(String(localized: "meter.delete.confirm.message \(meter.name)"))
        }
        .preferredColorScheme(appearanceMode.preferredColorScheme)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView(meters: activeMeters) { meter in
                selection = .meter(meter.id)
            }
        case .meter(let id):
            if let meter = meters.first(where: { $0.id == id }) {
                MeterDetailView(
                    meter: meter,
                    onAddReading: { activeSheet = .addReading(meter) },
                    onEditMeter: { activeSheet = .editMeter(meter) },
                    onDeleteMeter: { deletionCandidate = meter },
                    onEditReading: { activeSheet = .editReading($0) },
                    onDeleteReading: delete
                )
            } else {
                EmptyStateView(
                    title: String(localized: "meter.missing.title"),
                    message: String(localized: "meter.missing.message"),
                    systemImage: "questionmark.folder"
                )
            }
        }
    }

    private func createMeter(from draft: MeterDraft) {
        let meter = Meter(
            name: draft.name,
            kind: draft.kind,
            location: draft.location,
            unit: draft.unit,
            decimalPrecision: draft.decimalPrecision,
            isArchived: draft.isArchived,
            note: draft.note
        )

        if draft.unitPrice > 0 || draft.baseFee > 0 {
            meter.tariffs.append(
                MeterTariff(
                    currencyCode: draft.currencyCode,
                    unitPrice: draft.unitPrice,
                    baseFee: draft.baseFee,
                    meter: meter
                )
            )
        }

        if draft.usesBillingPeriod {
            meter.billingPeriods.append(
                BillingPeriod(
                    startsAt: draft.billingPeriodStart,
                    endsAt: draft.billingPeriodEnd,
                    label: draft.billingPeriodLabel,
                    meter: meter
                )
            )
        }

        modelContext.insert(meter)
        selection = .meter(meter.id)
    }

    private func update(_ meter: Meter, from draft: MeterDraft) {
        meter.name = draft.name
        meter.kind = draft.kind
        meter.location = draft.location
        meter.unit = draft.unit
        meter.decimalPrecision = draft.decimalPrecision
        meter.isArchived = draft.isArchived
        meter.note = draft.note
        meter.updatedAt = Date()

        let hasConfiguredTariff = draft.unitPrice > 0 || draft.baseFee > 0
        if hasConfiguredTariff {
            let existingTariff = meter.activeTariff
            let tariff = existingTariff ?? MeterTariff()
            tariff.currencyCode = draft.currencyCode
            tariff.unitPrice = draft.unitPrice
            tariff.baseFee = draft.baseFee
            tariff.validFrom = Date()
            if existingTariff == nil {
                tariff.meter = meter
                meter.tariffs.append(tariff)
            }
        } else {
            for tariff in meter.tariffs {
                modelContext.delete(tariff)
            }
        }

        if draft.usesBillingPeriod {
            let existingPeriod = meter.activeBillingPeriod
            let period = existingPeriod ?? BillingPeriod(
                startsAt: draft.billingPeriodStart,
                endsAt: draft.billingPeriodEnd
            )
            period.startsAt = draft.billingPeriodStart
            period.endsAt = draft.billingPeriodEnd
            period.label = draft.billingPeriodLabel
            if existingPeriod == nil {
                period.meter = meter
                meter.billingPeriods.append(period)
            }
        } else {
            for period in meter.billingPeriods {
                modelContext.delete(period)
            }
        }
    }

    private func delete(_ meter: Meter) {
        modelContext.delete(meter)
        if selection == .meter(meter.id) {
            selection = .dashboard
        }
        deletionCandidate = nil
    }

    private func createReading(for meter: Meter, from draft: ReadingDraft) {
        let recordedAt = MeterAnalytics.normalizedToDisplayedMinute(draft.recordedAt)
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            existingReadings: meter.readings
        )
        guard validation.canSave else { return }

        let reading = MeterReading(
            value: draft.value,
            recordedAt: recordedAt,
            note: draft.note,
            meter: meter
        )
        meter.readings.append(reading)
        meter.updatedAt = Date()
    }

    private func update(_ reading: MeterReading, from draft: ReadingDraft) {
        let recordedAt = MeterAnalytics.normalizedToDisplayedMinute(draft.recordedAt)
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            existingReadings: reading.meter?.readings ?? [],
            editingReadingID: reading.id
        )
        guard validation.canSave else { return }

        reading.value = draft.value
        reading.recordedAt = recordedAt
        reading.note = draft.note
        reading.updatedAt = Date()
        reading.meter?.updatedAt = Date()
    }

    private func delete(_ reading: MeterReading) {
        reading.meter?.updatedAt = Date()
        modelContext.delete(reading)
    }
}

struct AppearanceModeMenu: View {
    @Binding var selection: String
    let currentMode: AppearanceMode

    var body: some View {
        Menu {
            Picker(String(localized: "appearance.title"), selection: $selection) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.localizedTitle, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
        } label: {
            Label(String(localized: "appearance.title"), systemImage: currentMode.systemImage)
        }
        .help(String(localized: "appearance.title"))
    }
}

struct MeterSidebarRow: View {
    let meter: Meter

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(meter.name)
                if let latestReading = meter.latestReading {
                    Text(MeterFormatting.value(latestReading.value, unit: meter.unit, precision: meter.decimalPrecision))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: meter.kind.symbolName)
        }
        .accessibilityLabel(String(localized: "accessibility.meter.row \(meter.name)"))
    }
}

struct DashboardView: View {
    let meters: [Meter]
    let selectMeter: (Meter) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if meters.isEmpty {
                    EmptyStateView(
                        title: String(localized: "dashboard.empty.title"),
                        message: String(localized: "dashboard.empty.message"),
                        systemImage: "plus.square.dashed"
                    )
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
                Text(MeterFormatting.mediumDateTime(latestReading.recordedAt))
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
    }
}

struct MeterDetailView: View {
    let meter: Meter
    let onAddReading: () -> Void
    let onEditMeter: () -> Void
    let onDeleteMeter: () -> Void
    let onEditReading: (MeterReading) -> Void
    let onDeleteReading: (MeterReading) -> Void

    private var readingsAscending: [MeterReading] {
        meter.sortedReadingsAscending
    }

    private var readingsDescending: [MeterReading] {
        meter.sortedReadingsDescending
    }

    private var deltas: [ConsumptionDelta] {
        MeterAnalytics.consumptionDeltas(from: meter.readings)
    }

    private var forecast: ForecastResult? {
        let period = meter.activeBillingPeriod.map { ($0.startsAt, $0.endsAt) }
            ?? MeterAnalytics.defaultBillingPeriod(containing: Date())

        return MeterAnalytics.forecast(
            readings: meter.readings,
            periodStart: period.0,
            periodEnd: period.1,
            tariff: meter.activeTariff
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MeterHeaderView(meter: meter)

                MeterInsightGrid(meter: meter, forecast: forecast)

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
                        readings: readingsAscending,
                        deltas: deltas,
                        forecast: forecast
                    )

                    ReadingHistoryView(
                        meter: meter,
                        readings: readingsDescending,
                        onEdit: onEditReading,
                        onDelete: onDeleteReading
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

                Button(action: onEditMeter) {
                    Label(String(localized: "meter.edit"), systemImage: "slider.horizontal.3")
                }
                .help(String(localized: "meter.edit"))

                Button(role: .destructive, action: onDeleteMeter) {
                    Label(String(localized: "meter.delete"), systemImage: "trash")
                }
                .help(String(localized: "meter.delete"))
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
    let forecast: ForecastResult?

    var body: some View {
        let latest = meter.latestReading.map {
            MeterFormatting.value($0.value, unit: meter.unit, precision: meter.decimalPrecision)
        } ?? String(localized: "notAvailable")

        let lastDelta = MeterAnalytics.lastConsumptionDelta(from: meter.readings).map {
            MeterFormatting.value($0.value, unit: meter.unit, precision: meter.decimalPrecision)
        } ?? String(localized: "notAvailable")

        let average = MeterAnalytics.averageDailyConsumption(from: meter.readings).map {
            "\(MeterFormatting.decimal($0, precision: meter.decimalPrecision)) \(meter.unit)/\(String(localized: "day.short"))"
        } ?? String(localized: "notAvailable")

        let estimate = forecast.map {
            MeterFormatting.value($0.projectedConsumption, unit: meter.unit, precision: meter.decimalPrecision)
        } ?? String(localized: "forecast.insufficient.short")

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            InsightCard(title: String(localized: "insight.latest"), value: latest, systemImage: "speedometer")
            InsightCard(title: String(localized: "insight.lastDelta"), value: lastDelta, systemImage: "minus.forwardslash.plus")
            InsightCard(title: String(localized: "insight.averageDaily"), value: average, systemImage: "calendar")
            InsightCard(title: String(localized: "insight.periodEstimate"), value: estimate, systemImage: "chart.line.uptrend.xyaxis")
        }
    }
}

struct InsightCard: View {
    let title: String
    let value: String
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

                if let forecast, let latest = readings.last {
                    LineMark(
                        x: .value(String(localized: "chart.date"), latest.recordedAt),
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
            .accessibilityLabel(String(localized: "accessibility.reading.chart"))

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
                .accessibilityLabel(String(localized: "accessibility.consumption.chart"))
            }

            ForecastExplanationView(meter: meter, forecast: forecast)
        }
    }
}

struct ForecastExplanationView: View {
    let meter: Meter
    let forecast: ForecastResult?

    var body: some View {
        if let forecast {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "forecast.title"))
                    .font(.headline)
                Text(String(localized: "forecast.explanation \(MeterFormatting.value(forecast.projectedConsumption, unit: meter.unit, precision: meter.decimalPrecision)) \(MeterFormatting.shortDate(forecast.endsAt))"))
                    .foregroundStyle(.secondary)

                if let projectedCost = forecast.projectedCost, let tariff = meter.activeTariff {
                    Text(String(localized: "forecast.cost \(MeterFormatting.currency(projectedCost, currencyCode: tariff.currencyCode))"))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "readings.history"))
                .font(.title2.weight(.semibold))

            VStack(spacing: 0) {
                ForEach(readings) { reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(MeterFormatting.value(reading.value, unit: meter.unit, precision: meter.decimalPrecision))
                                .font(.headline.monospacedDigit())
                            Text(MeterFormatting.mediumDateTime(reading.recordedAt))
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
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                    if reading.id != readings.last?.id {
                        Divider()
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(24)
    }
}

struct MeterDraft {
    var name: String
    var kind: MeterKind
    var location: String
    var unit: String
    var decimalPrecision: Int
    var isArchived: Bool
    var note: String
    var currencyCode: String
    var unitPrice: Double
    var baseFee: Double
    var usesBillingPeriod: Bool
    var billingPeriodStart: Date
    var billingPeriodEnd: Date
    var billingPeriodLabel: String

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && decimalPrecision >= 0
            && (!usesBillingPeriod || billingPeriodEnd > billingPeriodStart)
    }

    static func empty() -> MeterDraft {
        let period = MeterAnalytics.defaultBillingPeriod(containing: Date())
        return MeterDraft(
            name: "",
            kind: .electricity,
            location: "",
            unit: MeterKind.electricity.defaultUnit,
            decimalPrecision: 1,
            isArchived: false,
            note: "",
            currencyCode: Locale.current.currency?.identifier ?? "EUR",
            unitPrice: 0,
            baseFee: 0,
            usesBillingPeriod: false,
            billingPeriodStart: period.0,
            billingPeriodEnd: period.1,
            billingPeriodLabel: ""
        )
    }

    static func from(_ meter: Meter) -> MeterDraft {
        let period = meter.activeBillingPeriod
        let defaultPeriod = MeterAnalytics.defaultBillingPeriod(containing: Date())
        let tariff = meter.activeTariff

        return MeterDraft(
            name: meter.name,
            kind: meter.kind,
            location: meter.location,
            unit: meter.unit,
            decimalPrecision: meter.decimalPrecision,
            isArchived: meter.isArchived,
            note: meter.note,
            currencyCode: tariff?.currencyCode ?? Locale.current.currency?.identifier ?? "EUR",
            unitPrice: tariff?.unitPrice ?? 0,
            baseFee: tariff?.baseFee ?? 0,
            usesBillingPeriod: period != nil,
            billingPeriodStart: period?.startsAt ?? defaultPeriod.0,
            billingPeriodEnd: period?.endsAt ?? defaultPeriod.1,
            billingPeriodLabel: period?.label ?? ""
        )
    }
}

enum MeterFormMode {
    case add
    case edit(Meter)

    var title: String {
        switch self {
        case .add:
            String(localized: "meter.add")
        case .edit:
            String(localized: "meter.edit")
        }
    }

    var initialDraft: MeterDraft {
        switch self {
        case .add:
            .empty()
        case .edit(let meter):
            .from(meter)
        }
    }
}

struct MeterFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: MeterFormMode
    let onSave: (MeterDraft) -> Void

    @State private var draft: MeterDraft

    init(mode: MeterFormMode, onSave: @escaping (MeterDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: mode.initialDraft)
    }

    var body: some View {
        Form {
            Section(String(localized: "meter.section.general")) {
                TextField(String(localized: "meter.name"), text: $draft.name)
                Picker(String(localized: "meter.kind"), selection: $draft.kind) {
                    ForEach(MeterKind.allCases) { kind in
                        Label(kind.localizedName, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
                .onChange(of: draft.kind) { _, newKind in
                    if draft.unit.isEmpty {
                        draft.unit = newKind.defaultUnit
                    }
                }
                TextField(String(localized: "meter.location"), text: $draft.location)
                TextField(String(localized: "meter.unit"), text: $draft.unit)
                Stepper(
                    String(localized: "meter.decimalPrecision \(draft.decimalPrecision)"),
                    value: $draft.decimalPrecision,
                    in: 0...6
                )
                Toggle(String(localized: "meter.archived"), isOn: $draft.isArchived)
            }

            Section(String(localized: "meter.section.tariff")) {
                TextField(String(localized: "meter.currency"), text: $draft.currencyCode)
                TextField(String(localized: "meter.unitPrice"), value: $draft.unitPrice, format: .number)
                TextField(String(localized: "meter.baseFee"), value: $draft.baseFee, format: .number)
            }

            Section(String(localized: "meter.section.billing")) {
                Toggle(String(localized: "billing.useCustom"), isOn: $draft.usesBillingPeriod)
                if draft.usesBillingPeriod {
                    TextField(String(localized: "billing.label"), text: $draft.billingPeriodLabel)
                    DatePicker(String(localized: "billing.start"), selection: $draft.billingPeriodStart, displayedComponents: .date)
                    DatePicker(String(localized: "billing.end"), selection: $draft.billingPeriodEnd, displayedComponents: .date)
                }
            }

            Section(String(localized: "meter.section.notes")) {
                TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .padding()
        .frame(width: 460)
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "save")) {
                    onSave(draft)
                    dismiss()
                }
                .disabled(!draft.canSave)
            }
        }
    }
}

struct ReadingDraft {
    var value: Double
    var recordedAt: Date
    var note: String

    static func empty() -> ReadingDraft {
        ReadingDraft(value: 0, recordedAt: MeterAnalytics.normalizedToDisplayedMinute(Date()), note: "")
    }

    static func from(_ reading: MeterReading) -> ReadingDraft {
        ReadingDraft(value: reading.value, recordedAt: reading.recordedAt, note: reading.note)
    }
}

enum ReadingValueParser {
    static func formatForEditing(_ value: Double, locale: Locale = .current) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let roundTrippingText = String(value)
        guard decimalSeparator != "." else { return roundTrippingText }

        return roundTrippingText.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false

        if let number = formatter.number(from: trimmedText) {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }

        let normalizedText = trimmedText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalizedText), value.isFinite else {
            return nil
        }

        return value
    }
}

enum ReadingFormMode {
    case add(Meter)
    case edit(MeterReading)

    var title: String {
        switch self {
        case .add:
            String(localized: "reading.add")
        case .edit:
            String(localized: "reading.edit")
        }
    }

    var meter: Meter? {
        switch self {
        case .add(let meter):
            meter
        case .edit(let reading):
            reading.meter
        }
    }

    var editingReadingID: UUID? {
        switch self {
        case .add:
            nil
        case .edit(let reading):
            reading.id
        }
    }

    var initialDraft: ReadingDraft {
        switch self {
        case .add:
            .empty()
        case .edit(let reading):
            .from(reading)
        }
    }
}

struct ReadingFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: ReadingFormMode
    let onSave: (ReadingDraft) -> Void

    @State private var draft: ReadingDraft
    @State private var valueText: String
    @FocusState private var valueFieldIsFocused: Bool

    init(mode: ReadingFormMode, onSave: @escaping (ReadingDraft) -> Void) {
        let initialDraft = mode.initialDraft
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _valueText = State(initialValue: mode.editingReadingID == nil ? "" : ReadingValueParser.formatForEditing(initialDraft.value))
    }

    private var parsedValue: Double? {
        ReadingValueParser.parse(valueText)
    }

    private var validation: ReadingValidationResult {
        guard let parsedValue else {
            return ReadingValidationResult(issues: [])
        }

        return MeterAnalytics.validateReading(
            value: parsedValue,
            recordedAt: MeterAnalytics.normalizedToDisplayedMinute(draft.recordedAt),
            existingReadings: mode.meter?.readings ?? [],
            editingReadingID: mode.editingReadingID
        )
    }

    private var visibleIssues: [ReadingValidationIssue] {
        if valueFieldIsFocused {
            validation.blockingIssues
        } else {
            validation.issues
        }
    }

    private var canSave: Bool {
        parsedValue != nil && validation.canSave
    }

    var body: some View {
        Form {
            Section(String(localized: "reading.section.value")) {
                TextField(String(localized: "reading.value"), text: $valueText)
                    .focused($valueFieldIsFocused)
                DatePicker(
                    String(localized: "reading.recordedAt"),
                    selection: $draft.recordedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            if !visibleIssues.isEmpty {
                Section(String(localized: "validation.title")) {
                    ForEach(visibleIssues, id: \.rawValue) { issue in
                        Label(issue.localizedMessage, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "save")) {
                    if let parsedValue {
                        var savedDraft = draft
                        savedDraft.value = parsedValue
                        onSave(savedDraft)
                        dismiss()
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}
