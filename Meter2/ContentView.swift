import AppKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isImportingCSV = false
    @State private var csvImportSession: CSVImportSession?
    @State private var importResult: CSVImportResult?
    @State private var importErrorMessage: String?
    @State private var exportResultMessage: String?
    @State private var exportErrorMessage: String?
    @State private var reportResultMessage: String?
    @State private var reportErrorMessage: String?
    @State private var persistenceErrorMessage: String?
    @State private var deletionCandidate: Meter?
    @State private var csvProgress: CSVProgressState?
    @State private var reportProgress: CSVProgressState?
    @State private var isShowingShortcutsHelp = false
    @State private var selectedStatisticsPeriod: StatisticsPeriod = .currentMonth
    @State private var customStatisticsStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customStatisticsEndDate = Date()

    private var activeMeters: [Meter] {
        meters.filter { !$0.isArchived }
    }

    private var archivedMeters: [Meter] {
        meters.filter(\.isArchived)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.mode(for: appearanceModeRawValue)
    }

    private var selectedMeter: Meter? {
        guard case .meter(let id) = selection else { return nil }
        return meters.first { $0.id == id }
    }

    private var isBusy: Bool {
        csvProgress != nil || reportProgress != nil
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
                        MeterSidebarRow(
                            meter: meter,
                            addReading: { showAddReading(for: meter) },
                            isAddDisabled: isBusy,
                            commands: meterContextCommands(for: meter)
                        )
                            .tag(SidebarSelection.meter(meter.id))
                    }
                }

                if !archivedMeters.isEmpty {
                    Section(String(localized: "navigation.archived")) {
                        ForEach(archivedMeters) { meter in
                            MeterSidebarRow(
                                meter: meter,
                                addReading: { showAddReading(for: meter) },
                                isAddDisabled: isBusy,
                                commands: meterContextCommands(for: meter)
                            )
                                .tag(SidebarSelection.meter(meter.id))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "app.name"))
            .toolbar {
                ToolbarItem {
                    Button {
                        showAddMeter()
                    } label: {
                        Label(String(localized: "meter.add"), systemImage: "plus")
                    }
                    .help(String(localized: "meter.add"))
                    .disabled(isBusy)
                }
                ToolbarItem {
                    Button {
                        showCSVImporter()
                    } label: {
                        Label(String(localized: "csv.import"), systemImage: "square.and.arrow.down")
                    }
                    .help(String(localized: "csv.import"))
                    .disabled(isBusy)
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
        .sheet(item: $csvImportSession) { session in
            CSVImportView(
                document: session.document,
                meters: meters,
                progressMessage: csvProgress?.message,
                onCancel: { csvImportSession = nil },
                onImport: importCSV
            )
        }
        .sheet(isPresented: $isShowingShortcutsHelp) {
            ShortcutsHelpView()
        }
        .overlay {
            if let csvProgress {
                ProgressOverlayView(message: csvProgress.message)
            } else if let reportProgress {
                ProgressOverlayView(message: reportProgress.message)
            }
        }
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleCSVFileSelection(result)
        }
        .alert(
            String(localized: "csv.importError.title"),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            String(localized: "csv.importResult.title"),
            isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            ),
            presenting: importResult
        ) { _ in
            Button(String(localized: "ok"), role: .cancel) {}
        } message: { result in
            Text(String(localized: "csv.importResult.message \(result.createdMeters) \(result.importedReadings) \(result.skippedDuplicates) \(result.skippedInvalidRows)"))
        }
        .alert(
            String(localized: "csv.exportResult.title"),
            isPresented: Binding(
                get: { exportResultMessage != nil },
                set: { if !$0 { exportResultMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(exportResultMessage ?? "")
        }
        .alert(
            String(localized: "csv.exportError.title"),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert(
            String(localized: "report.result.title"),
            isPresented: Binding(
                get: { reportResultMessage != nil },
                set: { if !$0 { reportResultMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(reportResultMessage ?? "")
        }
        .alert(
            String(localized: "report.error.title"),
            isPresented: Binding(
                get: { reportErrorMessage != nil },
                set: { if !$0 { reportErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(reportErrorMessage ?? "")
        }
        .alert(
            String(localized: "persistence.error.title"),
            isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: { if !$0 { persistenceErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage ?? "")
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
        .focusedSceneValue(\.meter2CommandActions, commandActions)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView(
                meters: activeMeters,
                selectMeter: { meter in
                    selection = .meter(meter.id)
                },
                meterCommands: meterContextCommands(for:)
            )
        case .meter(let id):
            if let meter = meters.first(where: { $0.id == id }) {
                MeterDetailView(
                    meter: meter,
                    isBusy: isBusy,
                    statisticsPeriod: $selectedStatisticsPeriod,
                    customStatisticsStartDate: $customStatisticsStartDate,
                    customStatisticsEndDate: $customStatisticsEndDate,
                    onAddReading: { activeSheet = .addReading(meter) },
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

    private func meterContextCommands(for meter: Meter) -> MeterContextCommands {
        MeterContextCommands(
            addReading: isBusy ? nil : { showAddReading(for: meter) },
            edit: isBusy ? nil : { showEditMeter(meter) },
            exportCSV: isBusy ? nil : { exportCSV(scope: .meter(meter.id)) },
            exportReport: isBusy ? nil : { exportReport(scope: .selectedMeter(meter.id)) },
            printReport: isBusy ? nil : { printReport(scope: .selectedMeter(meter.id)) },
            toggleArchiveTitle: meter.isArchived ? String(localized: "meter.unarchive") : String(localized: "meter.archive"),
            toggleArchive: isBusy ? nil : { setArchived(!meter.isArchived, for: meter) },
            delete: isBusy ? nil : { confirmDeleteMeter(meter) }
        )
    }

    private func showEditMeter(_ meter: Meter) {
        guard !isBusy else { return }
        selection = .meter(meter.id)
        activeSheet = .editMeter(meter)
    }

    private func confirmDeleteMeter(_ meter: Meter) {
        guard !isBusy else { return }
        selection = .meter(meter.id)
        deletionCandidate = meter
    }

    private func setArchived(_ isArchived: Bool, for meter: Meter) {
        guard !isBusy else { return }
        if persistChanges({
            meter.isArchived = isArchived
            meter.updatedAt = Date()
        }) {
            selection = .meter(meter.id)
        }
    }

    private func createMeter(from draft: MeterDraft) -> Bool {
        var createdMeter: Meter?
        let didSave = persistChanges {
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
            createdMeter = meter
        }

        if didSave, let createdMeter {
            selection = .meter(createdMeter.id)
        }
        return didSave
    }

    private func showAddMeter() {
        guard !isBusy else { return }
        activeSheet = .addMeter
    }

    private func showAddReading() {
        guard !isBusy, let selectedMeter else { return }
        activeSheet = .addReading(selectedMeter)
    }

    private func showAddReading(for meter: Meter) {
        guard !isBusy else { return }
        selection = .meter(meter.id)
        activeSheet = .addReading(meter)
    }

    private func showEditSelectedMeter() {
        guard !isBusy, let selectedMeter else { return }
        showEditMeter(selectedMeter)
    }

    private func confirmDeleteSelectedMeter() {
        guard !isBusy, let selectedMeter else { return }
        confirmDeleteMeter(selectedMeter)
    }

    private func showCSVImporter() {
        guard !isBusy else { return }
        isImportingCSV = true
    }

    private func update(_ meter: Meter, from draft: MeterDraft) -> Bool {
        persistChanges {
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
    }

    private func delete(_ meter: Meter) {
        if persistChanges({
            modelContext.delete(meter)
        }) {
            if selection == .meter(meter.id) {
                selection = .dashboard
            }
            deletionCandidate = nil
        }
    }

    private func createReading(for meter: Meter, from draft: ReadingDraft) -> Bool {
        let recordedAt = MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity)
        let now = Date()
        let readingID = UUID()
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            existingReadings: meter.readings
        )
        guard validation.canSave else { return false }
        return persistChanges {
            let reading = MeterReading(
                id: readingID,
                value: draft.value,
                recordedAt: recordedAt,
                recordedAtGranularity: draft.granularity,
                note: draft.note,
                meter: meter
            )
            meter.readings.append(reading)
            meter.updatedAt = now
        }
    }

    private func update(_ reading: MeterReading, from draft: ReadingDraft) -> Bool {
        let recordedAt = MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity)
        let now = Date()
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            existingReadings: reading.meter?.readings ?? [],
            editingReadingID: reading.id
        )
        guard validation.canSave else { return false }

        return persistChanges {
            reading.value = draft.value
            reading.recordedAt = recordedAt
            reading.recordedAtGranularity = draft.granularity
            reading.note = draft.note
            reading.updatedAt = now
            reading.meter?.updatedAt = now
        }
    }

    private func delete(_ reading: MeterReading) {
        _ = persistChanges {
            reading.meter?.updatedAt = Date()
            modelContext.delete(reading)
        }
    }

    private func handleCSVFileSelection(_ result: Result<[URL], Error>) {
        guard !isBusy else { return }

        do {
            guard let url = try result.get().first else { return }
            csvProgress = CSVProgressState(message: String(localized: "csv.progress.parsing"))

            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw CSVFileAccessError.accessDenied
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let document = try await Task.detached(priority: .userInitiated) {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        return try CSVParser.parse(text)
                    }.value

                    csvImportSession = CSVImportSession(document: document)
                } catch CSVFileAccessError.accessDenied {
                    importErrorMessage = String(localized: "csv.importError.access")
                } catch {
                    importErrorMessage = error.localizedDescription
                }

                csvProgress = nil
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importCSV(mapping: CSVColumnMapping, previewRows: [CSVImportPreviewRow]) {
        csvProgress = CSVProgressState(message: String(localized: "csv.progress.importing"))

        Task {
            await Task.yield()
            let importPlan = await Task.detached(priority: .userInitiated) {
                CSVImportExecutionPlan(
                    plannedReadings: previewRows.compactMap(\.plannedReading),
                    newMeterDrafts: CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows),
                    result: CSVImportPlanner.result(from: previewRows)
                )
            }.value

            let wasAutosaveEnabled = modelContext.autosaveEnabled
            modelContext.autosaveEnabled = false
            defer {
                modelContext.autosaveEnabled = wasAutosaveEnabled
                csvProgress = nil
            }

            var importedMetersByKey: [String: Meter] = [:]

            for draft in importPlan.newMeterDrafts {
                let meter = Meter(
                    name: draft.name,
                    kind: .custom,
                    location: draft.location,
                    unit: draft.unit,
                    decimalPrecision: draft.decimalPrecision
                )
                modelContext.insert(meter)
                importedMetersByKey[draft.key] = meter
            }

            for (index, plannedReading) in importPlan.plannedReadings.enumerated() {
                let meter: Meter?
                switch plannedReading.meterReference {
                case .existing(let id):
                    meter = meters.first { $0.id == id }
                case .new(let key):
                    meter = importedMetersByKey[key]
                }

                guard let meter else { continue }
                let now = Date()
                let readingID = UUID()
                meter.readings.append(
                    MeterReading(
                        id: readingID,
                        value: plannedReading.value,
                        recordedAt: plannedReading.recordedAt,
                        recordedAtGranularity: plannedReading.granularity,
                        note: plannedReading.note,
                        createdAt: now,
                        updatedAt: now,
                        meter: meter
                    )
                )
                meter.updatedAt = now

                if index.isMultiple(of: 100) {
                    await Task.yield()
                }
            }

            if savePendingChanges() {
                csvImportSession = nil
                importResult = importPlan.result
            }
        }
    }

    private func persistChanges(_ changes: () -> Void) -> Bool {
        handlePersistenceResult(PersistenceCommitter.commit(using: modelContext, changes: changes))
    }

    private func savePendingChanges() -> Bool {
        handlePersistenceResult(PersistenceCommitter.savePendingChanges(using: modelContext))
    }

    private func handlePersistenceResult(_ result: Result<Void, Error>) -> Bool {
        switch result {
        case .success:
            return true
        case .failure(let error):
            persistenceErrorMessage = String(localized: "persistence.error.message \(error.localizedDescription)")
            return false
        }
    }

    private func exportCSV(scope: CSVExportScope) {
        guard !isBusy else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = CSVExporter.suggestedFileName(for: scope, meters: meters)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            csvProgress = CSVProgressState(message: String(localized: "csv.progress.exporting"))
            let exportRecords = snapshotExportRecords(scope: scope)

            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let csv = CSVExporter.export(records: exportRecords)
                        try csv.write(to: url, atomically: true, encoding: .utf8)
                    }.value
                    exportResultMessage = String(localized: "csv.exportResult.message")
                } catch {
                    exportErrorMessage = error.localizedDescription
                }

                csvProgress = nil
            }
        }
    }

    private func exportReport(scope: ReportScope) {
        guard !isBusy else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = PDFReportGenerator.suggestedFileName(for: scope, meters: meters)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            reportProgress = CSVProgressState(message: String(localized: "report.progress.generating"))
            let snapshots = reportSnapshots(scope: scope)

            Task {
                do {
                    let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: scope)
                    try data.write(to: url, options: .atomic)
                    reportResultMessage = String(localized: "report.export.success")
                } catch {
                    reportErrorMessage = error.localizedDescription
                }

                reportProgress = nil
            }
        }
    }

    private func printReport(scope: ReportScope) {
        guard !isBusy else { return }

        reportProgress = CSVProgressState(message: String(localized: "report.progress.generating"))
        let snapshots = reportSnapshots(scope: scope)

        Task {
            do {
                let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: scope)

                reportProgress = nil

                guard let document = PDFDocument(data: data) else {
                    reportErrorMessage = String(localized: "report.error.invalidPDF")
                    return
                }

                let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
                printInfo.horizontalPagination = .fit
                printInfo.verticalPagination = .fit
                printInfo.isHorizontallyCentered = true
                printInfo.isVerticallyCentered = false

                if let operation = document.printOperation(
                    for: printInfo,
                    scalingMode: .pageScaleDownToFit,
                    autoRotate: true
                ) {
                    operation.jobTitle = String(localized: "report.print.jobTitle")
                    operation.run()
                } else {
                    reportErrorMessage = String(localized: "report.error.printUnavailable")
                }
            } catch {
                reportProgress = nil
                reportErrorMessage = error.localizedDescription
            }
        }
    }

    private func snapshotExportRecords(scope: CSVExportScope) -> [CSVExportRecord] {
        let scopedMeters: [Meter]
        switch scope {
        case .allReadings:
            scopedMeters = meters
        case .meter(let id):
            scopedMeters = meters.filter { $0.id == id }
        }

        return scopedMeters.flatMap { meter in
            meter.readings.map { reading in
                CSVExportRecord(
                    meterName: meter.name,
                    value: reading.value,
                    unit: meter.unit,
                    note: reading.note,
                    recordedAt: reading.recordedAt,
                    granularity: reading.recordedAtGranularity,
                    readingID: reading.id
                )
            }
        }
    }

    private func reportSnapshots(scope: ReportScope) -> [MeterReportSnapshot] {
        PDFReportGenerator.snapshots(
            meters: meters,
            scope: scope,
            selectedPeriod: selectedStatisticsPeriod,
            customStartDate: customStatisticsStartDate,
            customEndDate: customStatisticsEndDate
        )
    }

    private var commandActions: Meter2CommandActions {
        return Meter2CommandActions(
            addMeter: isBusy ? nil : showAddMeter,
            addReading: isBusy || selectedMeter == nil ? nil : showAddReading,
            editSelectedMeter: isBusy || selectedMeter == nil ? nil : showEditSelectedMeter,
            deleteSelectedMeter: isBusy || selectedMeter == nil ? nil : confirmDeleteSelectedMeter,
            importCSV: isBusy ? nil : showCSVImporter,
            exportContextualCSV: isBusy ? nil : { exportCSV(scope: selectedMeter.map { .meter($0.id) } ?? .allReadings) },
            exportAllReadingsCSV: isBusy ? nil : { exportCSV(scope: .allReadings) },
            exportSelectedMeterCSV: isBusy || selectedMeter == nil ? nil : {
                if let selectedMeter {
                    exportCSV(scope: .meter(selectedMeter.id))
                }
            },
            exportSelectedMeterReport: isBusy || selectedMeter == nil ? nil : {
                if let selectedMeter {
                    exportReport(scope: .selectedMeter(selectedMeter.id))
                }
            },
            printSelectedMeterReport: isBusy || selectedMeter == nil ? nil : {
                if let selectedMeter {
                    printReport(scope: .selectedMeter(selectedMeter.id))
                }
            },
            exportAllActiveMetersReport: isBusy ? nil : { exportReport(scope: .allActiveMeters) },
            printAllActiveMetersReport: isBusy ? nil : { printReport(scope: .allActiveMeters) },
            showHelp: { isShowingShortcutsHelp = true }
        )
    }
}

struct AppearanceModeMenu: View {
    @Binding var selection: String
    let currentMode: AppearanceMode

    var body: some View {
        Menu {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    selection = mode.rawValue
                } label: {
                    Label(mode.localizedTitle, systemImage: mode == currentMode ? "checkmark" : mode.systemImage)
                }
            }
        } label: {
            Label(String(localized: "appearance.title"), systemImage: currentMode.systemImage)
        }
        .help(String(localized: "appearance.title"))
    }
}

struct ProgressOverlayView: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
            }
            .padding(20)
            .frame(width: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
        }
    }
}

struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        (String(localized: "help.shortcut.key.addMeter"), String(localized: "help.shortcut.addMeter")),
        (String(localized: "help.shortcut.key.addReading"), String(localized: "help.shortcut.addReading")),
        (String(localized: "help.shortcut.key.importCSV"), String(localized: "help.shortcut.importCSV")),
        (String(localized: "help.shortcut.key.exportCSV"), String(localized: "help.shortcut.exportCSV")),
        (String(localized: "help.shortcut.key.focusSearch"), String(localized: "help.shortcut.focusSearch")),
        (String(localized: "help.shortcut.key.help"), String(localized: "help.shortcut.help"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(localized: "help.shortcuts"))
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(shortcuts, id: \.0) { shortcut, action in
                    GridRow {
                        Text(shortcut)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Text(action)
                    }
                }
            }

            HStack {
                Spacer()
                Button(String(localized: "close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct MeterSidebarRow: View {
    let meter: Meter
    let addReading: () -> Void
    let isAddDisabled: Bool
    let commands: MeterContextCommands

    var body: some View {
        HStack(spacing: 8) {
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
                    .foregroundStyle(meter.kind.tintColor)
            }
            .accessibilityLabel(String(localized: "accessibility.meter.row \(meter.name)"))

            Spacer(minLength: 4)

            Button(action: addReading) {
                Label(String(localized: "reading.add"), systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "accessibility.reading.addForMeter \(meter.name)"))
            .disabled(isAddDisabled)
            .accessibilityLabel(String(localized: "accessibility.reading.addForMeter \(meter.name)"))
        }
        .contextMenu {
            MeterContextMenu(commands: commands)
        }
    }
}

struct MeterContextCommands {
    var addReading: (() -> Void)?
    var edit: (() -> Void)?
    var exportCSV: (() -> Void)?
    var exportReport: (() -> Void)?
    var printReport: (() -> Void)?
    var toggleArchiveTitle: String
    var toggleArchive: (() -> Void)?
    var delete: (() -> Void)?
}

struct MeterContextMenu: View {
    let commands: MeterContextCommands

    var body: some View {
        Button(String(localized: "reading.add")) {
            commands.addReading?()
        }
        .disabled(commands.addReading == nil)

        Button(String(localized: "meter.edit")) {
            commands.edit?()
        }
        .disabled(commands.edit == nil)

        Divider()

        Button(String(localized: "csv.export.selectedMeter")) {
            commands.exportCSV?()
        }
        .disabled(commands.exportCSV == nil)

        Button(String(localized: "report.export.selected")) {
            commands.exportReport?()
        }
        .disabled(commands.exportReport == nil)

        Button(String(localized: "report.print.selected")) {
            commands.printReport?()
        }
        .disabled(commands.printReport == nil)

        Divider()

        Button(commands.toggleArchiveTitle) {
            commands.toggleArchive?()
        }
        .disabled(commands.toggleArchive == nil)

        Button(String(localized: "meter.delete"), role: .destructive) {
            commands.delete?()
        }
        .disabled(commands.delete == nil)
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
