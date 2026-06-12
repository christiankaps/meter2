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
    @EnvironmentObject private var syncService: MeterLibrarySyncService
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
    @State private var deletionCandidate: Meter?
    @State private var csvProgress: CSVProgressState?
    @State private var reportProgress: CSVProgressState?
    @State private var isShowingShortcutsHelp = false
    @State private var isConfirmingSyncEnable = false
    @State private var syncErrorMessage: String?
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

    private var canManageLibrary: Bool {
        syncService.status == .disabled || MeterLibraryPermissionPolicy.canPerform(.editMeter, role: syncService.currentRole)
    }

    private var canDeleteReadings: Bool {
        syncService.status == .disabled || MeterLibraryPermissionPolicy.canPerform(.deleteReading, role: syncService.currentRole)
    }

    private var syncStatusText: String {
        switch syncService.status {
        case .disabled:
            String(localized: "sync.status.disabled")
        case .idle:
            String(localized: "sync.status.idle")
        case .syncing:
            String(localized: "sync.status.syncing")
        case .offline:
            String(localized: "sync.status.offline")
        case .failed:
            String(localized: "sync.status.failed")
        }
    }

    private var syncRoleText: String {
        switch syncService.currentRole {
        case .owner:
            String(localized: "sync.role.owner")
        case .collaborator:
            String(localized: "sync.role.collaborator")
        }
    }

    private var syncIconName: String {
        switch syncService.status {
        case .disabled:
            "icloud.slash"
        case .idle:
            "icloud"
        case .syncing:
            "icloud.and.arrow.up"
        case .offline:
            "wifi.slash"
        case .failed:
            "exclamationmark.icloud"
        }
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
                    .disabled(isBusy || !canManageLibrary)
                }
                ToolbarItem {
                    Button {
                        showCSVImporter()
                    } label: {
                        Label(String(localized: "csv.import"), systemImage: "square.and.arrow.down")
                    }
                    .help(String(localized: "csv.import"))
                    .disabled(isBusy || !canManageLibrary)
                }
                ToolbarItem {
                    Menu {
                        Button {
                            exportCSV(scope: .allReadings)
                        } label: {
                            Label(String(localized: "csv.export.all"), systemImage: "tray.and.arrow.up")
                        }

                        Button {
                            if let selectedMeter {
                                exportCSV(scope: .meter(selectedMeter.id))
                            }
                        } label: {
                            Label(String(localized: "csv.export.selectedMeter"), systemImage: "doc")
                        }
                        .disabled(selectedMeter == nil)
                    } label: {
                        Label(String(localized: "csv.export"), systemImage: "square.and.arrow.up")
                    }
                    .help(String(localized: "csv.export"))
                    .disabled(isBusy)
                }
                ToolbarItem {
                    Menu {
                        Button {
                            if let selectedMeter {
                                exportReport(scope: .selectedMeter(selectedMeter.id))
                            }
                        } label: {
                            Label(String(localized: "report.export.selected"), systemImage: "doc.badge.arrow.up")
                        }
                        .disabled(selectedMeter == nil)

                        Button {
                            if let selectedMeter {
                                printReport(scope: .selectedMeter(selectedMeter.id))
                            }
                        } label: {
                            Label(String(localized: "report.print.selected"), systemImage: "printer")
                        }
                        .disabled(selectedMeter == nil)

                        Divider()

                        Button {
                            exportReport(scope: .allActiveMeters)
                        } label: {
                            Label(String(localized: "report.export.allActive"), systemImage: "doc.on.doc")
                        }

                        Button {
                            printReport(scope: .allActiveMeters)
                        } label: {
                            Label(String(localized: "report.print.allActive"), systemImage: "printer.filled.and.paper")
                        }
                    } label: {
                        Label(String(localized: "report.menu"), systemImage: "doc.richtext")
                    }
                    .help(String(localized: "report.menu"))
                    .disabled(isBusy)
                }
                ToolbarItem {
                    Menu {
                        if syncService.status == .disabled {
                            Button {
                                isConfirmingSyncEnable = true
                            } label: {
                                Label(String(localized: "sync.enable"), systemImage: "icloud.and.arrow.up")
                            }
                        } else {
                            Button {
                                syncNow()
                            } label: {
                                Label(String(localized: "sync.now"), systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Divider()

                        Label(syncStatusText, systemImage: syncIconName)
                        Label(syncRoleText, systemImage: "person.crop.circle")
                    } label: {
                        Label(syncStatusText, systemImage: syncIconName)
                    }
                    .help(String(localized: "sync.menu"))
                    .disabled(isBusy || syncService.status == .syncing)
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
            String(localized: "sync.error.title"),
            isPresented: Binding(
                get: { syncErrorMessage != nil },
                set: { if !$0 { syncErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(syncErrorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "sync.enable.confirm.title"),
            isPresented: $isConfirmingSyncEnable
        ) {
            Button(String(localized: "sync.enable.confirm.button")) {
                enableSync()
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "sync.enable.confirm.message"))
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
                    onEditMeter: { activeSheet = .editMeter(meter) },
                    onDeleteMeter: { deletionCandidate = meter },
                    onEditReading: { activeSheet = .editReading($0) },
                    onDeleteReading: delete,
                    canManageMeter: canManageLibrary,
                    canDeleteReadings: canDeleteReadings
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
            edit: isBusy || !canManageLibrary ? nil : { showEditMeter(meter) },
            exportCSV: isBusy ? nil : { exportCSV(scope: .meter(meter.id)) },
            exportReport: isBusy ? nil : { exportReport(scope: .selectedMeter(meter.id)) },
            printReport: isBusy ? nil : { printReport(scope: .selectedMeter(meter.id)) },
            toggleArchiveTitle: meter.isArchived ? String(localized: "meter.unarchive") : String(localized: "meter.archive"),
            toggleArchive: isBusy || !canManageLibrary ? nil : { setArchived(!meter.isArchived, for: meter) },
            delete: isBusy || !canManageLibrary ? nil : { confirmDeleteMeter(meter) }
        )
    }

    private func showEditMeter(_ meter: Meter) {
        guard !isBusy, canManageLibrary else { return }
        selection = .meter(meter.id)
        activeSheet = .editMeter(meter)
    }

    private func confirmDeleteMeter(_ meter: Meter) {
        guard !isBusy, canManageLibrary else { return }
        selection = .meter(meter.id)
        deletionCandidate = meter
    }

    private func setArchived(_ isArchived: Bool, for meter: Meter) {
        guard !isBusy, canManageLibrary, ensureSyncPermission(.archiveMeter) else { return }
        meter.isArchived = isArchived
        meter.updatedAt = Date()
        _ = enqueueSyncOperationIfNeeded(.upsertMeter(MeterSyncRecord(meter: meter)))
        selection = .meter(meter.id)
    }

    private func createMeter(from draft: MeterDraft) {
        guard ensureSyncPermission(.createMeter) else { return }
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

        guard enqueueMeterSnapshotIfNeeded(meter) else { return }
        modelContext.insert(meter)
        selection = .meter(meter.id)
    }

    private func showAddMeter() {
        guard !isBusy, canManageLibrary else { return }
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
        guard !isBusy, canManageLibrary, let selectedMeter else { return }
        showEditMeter(selectedMeter)
    }

    private func confirmDeleteSelectedMeter() {
        guard !isBusy, canManageLibrary, let selectedMeter else { return }
        confirmDeleteMeter(selectedMeter)
    }

    private func showCSVImporter() {
        guard !isBusy, canManageLibrary else { return }
        isImportingCSV = true
    }

    private func update(_ meter: Meter, from draft: MeterDraft) {
        guard ensureSyncPermission(.editMeter) else { return }
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
                guard enqueueSyncOperationIfNeeded(.deleteTariff(tariff.id)) else { return }
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
                guard enqueueSyncOperationIfNeeded(.deleteBillingPeriod(period.id)) else { return }
                modelContext.delete(period)
            }
        }

        _ = enqueueSyncOperationIfNeeded(.upsertMeter(MeterSyncRecord(meter: meter)))
        if hasConfiguredTariff, let record = meter.activeTariff.flatMap(MeterTariffSyncRecord.init(tariff:)) {
            _ = enqueueSyncOperationIfNeeded(.upsertTariff(record))
        }
        if draft.usesBillingPeriod, let record = meter.activeBillingPeriod.flatMap(BillingPeriodSyncRecord.init(period:)) {
            _ = enqueueSyncOperationIfNeeded(.upsertBillingPeriod(record))
        }
    }

    private func delete(_ meter: Meter) {
        guard ensureSyncPermission(.deleteMeter),
              enqueueSyncOperationIfNeeded(.deleteMeter(meter.id)) else { return }
        modelContext.delete(meter)
        if selection == .meter(meter.id) {
            selection = .dashboard
        }
        deletionCandidate = nil
    }

    private func createReading(for meter: Meter, from draft: ReadingDraft) {
        guard ensureSyncPermission(.addReading) else { return }
        let recordedAt = MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity)
        let now = Date()
        let readingID = UUID()
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            existingReadings: meter.readings
        )
        guard validation.canSave else { return }
        let syncRecord = MeterReadingSyncRecord(
            id: readingID,
            meterID: meter.id,
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            note: draft.note,
            createdAt: now,
            updatedAt: now
        )
        guard enqueueSyncOperationIfNeeded(.upsertReading(syncRecord)) else { return }

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

    private func update(_ reading: MeterReading, from draft: ReadingDraft) {
        guard ensureSyncPermission(.editReading) else { return }
        let recordedAt = MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity)
        let now = Date()
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            existingReadings: reading.meter?.readings ?? [],
            editingReadingID: reading.id
        )
        guard validation.canSave else { return }

        reading.value = draft.value
        reading.recordedAt = recordedAt
        reading.recordedAtGranularity = draft.granularity
        reading.note = draft.note
        reading.updatedAt = now
        reading.meter?.updatedAt = now
        if let syncRecord = MeterReadingSyncRecord(reading: reading) {
            _ = enqueueSyncOperationIfNeeded(.upsertReading(syncRecord))
        }
    }

    private func delete(_ reading: MeterReading) {
        guard ensureSyncPermission(.deleteReading),
              enqueueSyncOperationIfNeeded(.deleteReading(reading.id)) else { return }
        reading.meter?.updatedAt = Date()
        modelContext.delete(reading)
    }

    private func enableSync() {
        do {
            try syncService.enableSync(for: meters)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private func syncNow() {
        do {
            _ = try syncService.syncNow()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    private func ensureSyncPermission(_ action: MeterLibraryAction) -> Bool {
        guard syncService.status != .disabled else { return true }
        guard MeterLibraryPermissionPolicy.canPerform(action, role: syncService.currentRole) else {
            syncErrorMessage = MeterLibrarySyncError.permissionDenied(action).localizedDescription
            return false
        }
        return true
    }

    private func enqueueSyncOperationIfNeeded(_ operation: MeterSyncOperation) -> Bool {
        guard syncService.status != .disabled else { return true }
        do {
            try syncService.enqueue(operation)
            return true
        } catch {
            syncErrorMessage = error.localizedDescription
            return false
        }
    }

    private func enqueueMeterSnapshotIfNeeded(_ meter: Meter) -> Bool {
        guard enqueueSyncOperationIfNeeded(.upsertMeter(MeterSyncRecord(meter: meter))) else { return false }
        for tariff in meter.tariffs {
            guard let record = MeterTariffSyncRecord(tariff: tariff),
                  enqueueSyncOperationIfNeeded(.upsertTariff(record)) else { return false }
        }
        for period in meter.billingPeriods {
            guard let record = BillingPeriodSyncRecord(period: period),
                  enqueueSyncOperationIfNeeded(.upsertBillingPeriod(record)) else { return false }
        }
        return true
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
        csvImportSession = nil

        Task {
            await Task.yield()
            let importPlan = await Task.detached(priority: .userInitiated) {
                CSVImportExecutionPlan(
                    plannedReadings: previewRows.compactMap(\.plannedReading),
                    newMeterDrafts: CSVImportPlanner.newMeterDrafts(from: mapping, previewRows: previewRows),
                    result: CSVImportPlanner.result(from: previewRows)
                )
            }.value

            var importedMetersByKey: [String: Meter] = [:]

            for draft in importPlan.newMeterDrafts {
                let meter = Meter(
                    name: draft.name,
                    kind: .custom,
                    location: draft.location,
                    unit: draft.unit,
                    decimalPrecision: draft.decimalPrecision
                )
                guard enqueueSyncOperationIfNeeded(.upsertMeter(MeterSyncRecord(meter: meter))) else {
                    csvProgress = nil
                    return
                }
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
                let syncRecord = MeterReadingSyncRecord(
                    id: readingID,
                    meterID: meter.id,
                    value: plannedReading.value,
                    recordedAt: plannedReading.recordedAt,
                    granularity: plannedReading.granularity,
                    note: plannedReading.note,
                    createdAt: now,
                    updatedAt: now
                )
                guard enqueueSyncOperationIfNeeded(.upsertReading(syncRecord)) else {
                    csvProgress = nil
                    return
                }

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

            importResult = importPlan.result
            csvProgress = nil
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
            addMeter: isBusy || !canManageLibrary ? nil : showAddMeter,
            addReading: isBusy || selectedMeter == nil ? nil : showAddReading,
            editSelectedMeter: isBusy || !canManageLibrary || selectedMeter == nil ? nil : showEditSelectedMeter,
            deleteSelectedMeter: isBusy || !canManageLibrary || selectedMeter == nil ? nil : confirmDeleteSelectedMeter,
            importCSV: isBusy || !canManageLibrary ? nil : showCSVImporter,
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
