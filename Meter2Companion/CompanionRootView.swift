import SwiftData
import SwiftUI

struct CompanionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: MeterLibrarySyncService
    @Query(sort: \Meter.name) private var meters: [Meter]
    @State private var selectedMeter: Meter?

    private var activeMeters: [Meter] {
        meters.filter { !$0.isArchived }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SyncStatusRow(status: syncService.status, role: syncService.currentRole)
                }

                Section(String(localized: "companion.meters")) {
                    if activeMeters.isEmpty {
                        ContentUnavailableView(
                            String(localized: "companion.empty.title"),
                            systemImage: "gauge.with.dots.needle.67percent",
                            description: Text(String(localized: "companion.empty.message"))
                        )
                    } else {
                        ForEach(activeMeters) { meter in
                            NavigationLink(value: meter) {
                                CompanionMeterRow(meter: meter)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "app.name"))
            .navigationDestination(for: Meter.self) { meter in
                CompanionMeterDetailView(meter: meter)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        _ = try? syncService.syncNow()
                    } label: {
                        Label(String(localized: "sync.now"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(syncService.status == .disabled)
                }
            }
        }
    }
}

private struct SyncStatusRow: View {
    let status: MeterLibrarySyncStatus
    let role: MeterLibraryRole

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                Text(roleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var statusText: String {
        switch status {
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

    private var roleText: String {
        switch role {
        case .owner:
            String(localized: "sync.role.owner")
        case .collaborator:
            String(localized: "sync.role.collaborator")
        }
    }

    private var iconName: String {
        switch status {
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

    private var iconColor: Color {
        switch status {
        case .disabled, .offline:
            .secondary
        case .idle:
            .blue
        case .syncing:
            .accentColor
        case .failed:
            .orange
        }
    }
}

private struct CompanionMeterRow: View {
    let meter: Meter

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(meter.name)
                if let latestReading = meter.latestReading {
                    Text(MeterFormatting.value(latestReading.value, unit: meter.unit, precision: meter.decimalPrecision))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "readings.empty.short"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: meter.kind.symbolName)
        }
    }
}

struct CompanionMeterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: MeterLibrarySyncService
    @Bindable var meter: Meter
    @State private var editedReading: MeterReading?
    @State private var isAddingReading = false
    @State private var syncErrorMessage: String?

    private var recentReadings: [MeterReading] {
        Array(meter.sortedReadingsDescending.prefix(10))
    }

    var body: some View {
        List {
            Section {
                if let latestReading = meter.latestReading {
                    LabeledContent(
                        String(localized: "companion.latestReading"),
                        value: MeterFormatting.value(latestReading.value, unit: meter.unit, precision: meter.decimalPrecision)
                    )
                    LabeledContent(String(localized: "reading.recordedAt"), value: MeterFormatting.readingDate(latestReading))
                } else {
                    ContentUnavailableView(
                        String(localized: "readings.empty.title"),
                        systemImage: "number",
                        description: Text(String(localized: "readings.empty.message"))
                    )
                }
            }

            Section(String(localized: "readings.history")) {
                ForEach(recentReadings) { reading in
                    Button {
                        editedReading = reading
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(MeterFormatting.value(reading.value, unit: meter.unit, precision: meter.decimalPrecision))
                                Text(MeterFormatting.readingDate(reading))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(meter.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingReading = true
                } label: {
                    Label(String(localized: "reading.add"), systemImage: "plus")
                }
                .disabled(!syncService.canCaptureReadings)
            }
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
        .sheet(isPresented: $isAddingReading) {
            NavigationStack {
                CompanionReadingFormView(meter: meter, reading: nil) { draft in
                    createReading(from: draft)
                }
            }
        }
        .sheet(item: $editedReading) { reading in
            NavigationStack {
                CompanionReadingFormView(meter: meter, reading: reading) { draft in
                    update(reading, from: draft)
                }
            }
        }
    }

    private func createReading(from draft: CompanionReadingDraft) -> Bool {
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
        do {
            try syncService.enqueue(.upsertReading(syncRecord))
        } catch {
            syncErrorMessage = error.localizedDescription
            return false
        }

        let reading = MeterReading(
            id: readingID,
            value: draft.value,
            recordedAt: recordedAt,
            recordedAtGranularity: draft.granularity,
            note: draft.note,
            createdAt: now,
            updatedAt: now,
            meter: meter
        )
        meter.readings.append(reading)
        meter.updatedAt = now
        return true
    }

    private func update(_ reading: MeterReading, from draft: CompanionReadingDraft) -> Bool {
        let recordedAt = MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity)
        let now = Date()
        let validation = MeterAnalytics.validateReading(
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            existingReadings: meter.readings,
            editingReadingID: reading.id
        )
        guard validation.canSave else { return false }

        let syncRecord = MeterReadingSyncRecord(
            id: reading.id,
            meterID: meter.id,
            value: draft.value,
            recordedAt: recordedAt,
            granularity: draft.granularity,
            note: draft.note,
            createdAt: reading.createdAt,
            updatedAt: now
        )
        do {
            try syncService.enqueue(.upsertReading(syncRecord))
        } catch {
            syncErrorMessage = error.localizedDescription
            return false
        }

        reading.value = draft.value
        reading.recordedAt = recordedAt
        reading.recordedAtGranularity = draft.granularity
        reading.note = draft.note
        reading.updatedAt = now
        meter.updatedAt = now
        return true
    }
}

private extension MeterLibrarySyncService {
    var canCaptureReadings: Bool {
        status != .disabled && MeterLibraryPermissionPolicy.canPerform(.addReading, role: currentRole)
    }
}
