import CloudKit
import Foundation
import SwiftData

enum MeterLibraryRole: String, Codable, Equatable {
    case owner
    case collaborator
}

enum MeterLibraryAction: Codable, Equatable {
    case createMeter
    case editMeter
    case archiveMeter
    case deleteMeter
    case manageTariffs
    case manageBillingPeriods
    case addReading
    case editReading
    case deleteReading
    case manageSharing
    case removeCloudCopy
}

enum MeterLibrarySyncStatus: Codable, Equatable {
    case disabled
    case idle
    case syncing
    case offline
    case failed(String)
}

enum MeterLibrarySyncError: LocalizedError, Equatable {
    case syncNotEnabled
    case permissionDenied(MeterLibraryAction)
    case missingLibrary

    var errorDescription: String? {
        switch self {
        case .syncNotEnabled:
            String(localized: "sync.error.notEnabled")
        case .permissionDenied:
            String(localized: "sync.error.permissionDenied")
        case .missingLibrary:
            String(localized: "sync.error.missingLibrary")
        }
    }
}

enum MeterLibraryPermissionPolicy {
    static func canPerform(_ action: MeterLibraryAction, role: MeterLibraryRole) -> Bool {
        switch role {
        case .owner:
            true
        case .collaborator:
            action == .addReading || action == .editReading
        }
    }
}

struct MeterSyncRecord: Codable, Equatable, Identifiable {
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

    init(meter: Meter) {
        id = meter.id
        name = meter.name
        kindRawValue = meter.kindRawValue
        location = meter.location
        unit = meter.unit
        decimalPrecision = meter.decimalPrecision
        isArchived = meter.isArchived
        note = meter.note
        createdAt = meter.createdAt
        updatedAt = meter.updatedAt
    }
}

struct MeterTariffSyncRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var meterID: UUID
    var currencyCode: String
    var unitPrice: Double
    var baseFee: Double
    var validFrom: Date
    var validUntil: Date?

    init?(tariff: MeterTariff) {
        guard let meterID = tariff.meter?.id else { return nil }
        id = tariff.id
        self.meterID = meterID
        currencyCode = tariff.currencyCode
        unitPrice = tariff.unitPrice
        baseFee = tariff.baseFee
        validFrom = tariff.validFrom
        validUntil = tariff.validUntil
    }
}

struct BillingPeriodSyncRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var meterID: UUID
    var startsAt: Date
    var endsAt: Date
    var label: String

    init?(period: BillingPeriod) {
        guard let meterID = period.meter?.id else { return nil }
        id = period.id
        self.meterID = meterID
        startsAt = period.startsAt
        endsAt = period.endsAt
        label = period.label
    }
}

struct MeterReadingSyncRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var meterID: UUID
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        meterID: UUID,
        value: Double,
        recordedAt: Date,
        granularity: ReadingTimestampGranularity,
        note: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.meterID = meterID
        self.value = value
        self.recordedAt = recordedAt
        self.granularity = granularity
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init?(reading: MeterReading) {
        guard let meterID = reading.meter?.id else { return nil }
        self.init(
            id: reading.id,
            meterID: meterID,
            value: reading.value,
            recordedAt: reading.recordedAt,
            granularity: reading.recordedAtGranularity,
            note: reading.note,
            createdAt: reading.createdAt,
            updatedAt: reading.updatedAt
        )
    }
}

enum MeterSyncOperation: Codable, Equatable, Identifiable {
    case upsertMeter(MeterSyncRecord)
    case deleteMeter(UUID)
    case upsertTariff(MeterTariffSyncRecord)
    case deleteTariff(UUID)
    case upsertBillingPeriod(BillingPeriodSyncRecord)
    case deleteBillingPeriod(UUID)
    case upsertReading(MeterReadingSyncRecord)
    case deleteReading(UUID)

    var id: String {
        switch self {
        case .upsertMeter(let record):
            "upsert-meter-\(record.id)"
        case .deleteMeter(let id):
            "delete-meter-\(id)"
        case .upsertTariff(let record):
            "upsert-tariff-\(record.id)"
        case .deleteTariff(let id):
            "delete-tariff-\(id)"
        case .upsertBillingPeriod(let record):
            "upsert-billing-period-\(record.id)"
        case .deleteBillingPeriod(let id):
            "delete-billing-period-\(id)"
        case .upsertReading(let record):
            "upsert-reading-\(record.id)"
        case .deleteReading(let id):
            "delete-reading-\(id)"
        }
    }

    var requiredAction: MeterLibraryAction {
        switch self {
        case .upsertMeter:
            .editMeter
        case .deleteMeter:
            .deleteMeter
        case .upsertTariff, .deleteTariff:
            .manageTariffs
        case .upsertBillingPeriod, .deleteBillingPeriod:
            .manageBillingPeriods
        case .upsertReading:
            .editReading
        case .deleteReading:
            .deleteReading
        }
    }
}

struct MeterSyncMergeResult: Equatable {
    var acceptedOperations: [MeterSyncOperation]
    var rejectedOperations: [MeterSyncOperation]
    var mergedReadings: [MeterReadingSyncRecord]
    var conflictsResolved: Int
}

struct MeterRemoteSyncOperation: Equatable {
    var operation: MeterSyncOperation
    private var verifiedAuthorRole: MeterLibraryRole

    static func verifiedOwnerChange(_ operation: MeterSyncOperation) -> MeterRemoteSyncOperation {
        MeterRemoteSyncOperation(operation: operation, verifiedAuthorRole: .owner)
    }

    static func verifiedCollaboratorChange(_ operation: MeterSyncOperation) -> MeterRemoteSyncOperation {
        MeterRemoteSyncOperation(operation: operation, verifiedAuthorRole: .collaborator)
    }

    var canApply: Bool {
        MeterLibraryPermissionPolicy.canPerform(operation.requiredAction, role: verifiedAuthorRole)
    }
}

struct MeterLibrarySyncState: Codable, Equatable {
    var status: MeterLibrarySyncStatus
    var currentRole: MeterLibraryRole
    var libraryID: UUID?
    var pendingOperations: [MeterSyncOperation]
}

protocol MeterLibrarySyncStateStore {
    func loadState() -> MeterLibrarySyncState?
    func saveState(_ state: MeterLibrarySyncState)
}

struct UserDefaultsMeterLibrarySyncStateStore: MeterLibrarySyncStateStore {
    private let key = "meter2.librarySync.state.v1"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadState() -> MeterLibrarySyncState? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MeterLibrarySyncState.self, from: data)
    }

    func saveState(_ state: MeterLibrarySyncState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: key)
    }
}

protocol MeterLibrarySharingClient {
    func shareLibrary(libraryID: UUID) async throws -> CKShare
    func acceptShare(metadata: CKShare.Metadata) async throws -> UUID
}

struct CloudKitMeterLibrarySharingClient: MeterLibrarySharingClient {
    private let zoneName = "Meter2Library"

    func shareLibrary(libraryID: UUID) async throws -> CKShare {
        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let rootRecordID = CKRecord.ID(
            recordName: libraryID.uuidString,
            zoneID: zoneID
        )
        let rootRecord = CKRecord(recordType: "MeterLibrary", recordID: rootRecordID)
        rootRecord["containerIdentifier"] = AppConfiguration.iCloudContainerIdentifier as CKRecordValue
        return CKShare(rootRecord: rootRecord)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws -> UUID {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.acceptSharesResultBlock = { result in
                continuation.resume(with: result)
            }
            CKContainer(identifier: AppConfiguration.iCloudContainerIdentifier).add(operation)
        }

        let recordName = metadata.rootRecordID.recordName
        guard let libraryID = UUID(uuidString: recordName) else {
            throw MeterLibrarySyncError.missingLibrary
        }
        return libraryID
    }
}

@MainActor
final class MeterLibrarySyncService: ObservableObject {
    @Published private(set) var status: MeterLibrarySyncStatus = .disabled
    @Published private(set) var currentRole: MeterLibraryRole = .owner
    @Published private(set) var libraryID: UUID?
    @Published private(set) var pendingOperations: [MeterSyncOperation] = []

    private let sharingClient: MeterLibrarySharingClient
    private let stateStore: MeterLibrarySyncStateStore

    init(
        sharingClient: MeterLibrarySharingClient = CloudKitMeterLibrarySharingClient(),
        stateStore: MeterLibrarySyncStateStore = UserDefaultsMeterLibrarySyncStateStore(),
        status: MeterLibrarySyncStatus = .disabled,
        currentRole: MeterLibraryRole = .owner,
        libraryID: UUID? = nil
    ) {
        self.sharingClient = sharingClient
        self.stateStore = stateStore
        if let restoredState = stateStore.loadState(), status == .disabled, libraryID == nil {
            self.status = restoredState.status
            self.currentRole = restoredState.currentRole
            self.libraryID = restoredState.libraryID
            self.pendingOperations = restoredState.pendingOperations
        } else {
            self.status = status
            self.currentRole = currentRole
            self.libraryID = libraryID
        }
    }

    func enableSync(for meters: [Meter], libraryID: UUID = UUID()) throws {
        self.libraryID = libraryID
        currentRole = .owner
        status = .idle
        pendingOperations = meters.map { .upsertMeter(MeterSyncRecord(meter: $0)) }
        pendingOperations += meters.flatMap { meter in
            meter.tariffs.compactMap(MeterTariffSyncRecord.init(tariff:)).map(MeterSyncOperation.upsertTariff)
        }
        pendingOperations += meters.flatMap { meter in
            meter.billingPeriods.compactMap(BillingPeriodSyncRecord.init(period:)).map(MeterSyncOperation.upsertBillingPeriod)
        }
        pendingOperations += meters.flatMap { meter in
            meter.readings.compactMap(MeterReadingSyncRecord.init(reading:)).map(MeterSyncOperation.upsertReading)
        }
        persistState()
    }

    func disableSyncKeepingLocalCopy() {
        status = .disabled
        libraryID = nil
        pendingOperations.removeAll()
        persistState()
    }

    func enqueue(_ operation: MeterSyncOperation) throws {
        guard status != .disabled else {
            throw MeterLibrarySyncError.syncNotEnabled
        }
        guard MeterLibraryPermissionPolicy.canPerform(operation.requiredAction, role: currentRole) else {
            throw MeterLibrarySyncError.permissionDenied(operation.requiredAction)
        }
        pendingOperations.append(operation)
        persistState()
    }

    func syncNow(remoteOperations: [MeterSyncOperation] = []) throws -> MeterSyncMergeResult {
        try syncNow(remoteOperations: remoteOperations.map {
            MeterRemoteSyncOperation.verifiedOwnerChange($0)
        })
    }

    func syncNow(remoteOperations: [MeterRemoteSyncOperation]) throws -> MeterSyncMergeResult {
        guard status != .disabled else {
            throw MeterLibrarySyncError.syncNotEnabled
        }

        status = .syncing
        let localOperations = pendingOperations

        let acceptedRemoteOperations = remoteOperations
            .filter(\.canApply)
            .map(\.operation)
        let rejectedRemoteOperations = remoteOperations
            .filter { !$0.canApply }
            .map(\.operation)

        let localReadings = localOperations.compactMap(\.readingRecord)
        let remoteReadings = acceptedRemoteOperations.compactMap(\.readingRecord)
        let mergedReadings = Self.mergeReadings(local: localReadings, remote: remoteReadings)
        let conflictCount = Set(localReadings.map(\.id)).intersection(remoteReadings.map(\.id)).count

        status = .idle
        persistState()
        return MeterSyncMergeResult(
            acceptedOperations: localOperations + acceptedRemoteOperations,
            rejectedOperations: rejectedRemoteOperations,
            mergedReadings: mergedReadings,
            conflictsResolved: conflictCount
        )
    }

    func shareLibrary() async throws -> CKShare {
        guard currentRole == .owner else {
            throw MeterLibrarySyncError.permissionDenied(.manageSharing)
        }
        guard let libraryID else {
            throw MeterLibrarySyncError.missingLibrary
        }
        return try await sharingClient.shareLibrary(libraryID: libraryID)
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        libraryID = try await sharingClient.acceptShare(metadata: metadata)
        currentRole = .collaborator
        status = .idle
        persistState()
    }

    static func mergeReadings(
        local: [MeterReadingSyncRecord],
        remote: [MeterReadingSyncRecord]
    ) -> [MeterReadingSyncRecord] {
        var recordsByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for remoteRecord in remote {
            guard let localRecord = recordsByID[remoteRecord.id] else {
                recordsByID[remoteRecord.id] = remoteRecord
                continue
            }

            if remoteRecord.updatedAt >= localRecord.updatedAt {
                recordsByID[remoteRecord.id] = remoteRecord
            }
        }

        return recordsByID.values.sorted { first, second in
            if first.recordedAt == second.recordedAt {
                return first.id.uuidString < second.id.uuidString
            }
            return first.recordedAt < second.recordedAt
        }
    }
}

private extension MeterSyncOperation {
    var readingRecord: MeterReadingSyncRecord? {
        switch self {
        case .upsertReading(let record):
            record
        case .upsertMeter, .deleteMeter, .upsertTariff, .deleteTariff, .upsertBillingPeriod, .deleteBillingPeriod, .deleteReading:
            nil
        }
    }
}

private extension MeterLibrarySyncService {
    func persistState() {
        stateStore.saveState(
            MeterLibrarySyncState(
                status: status,
                currentRole: currentRole,
                libraryID: libraryID,
                pendingOperations: pendingOperations
            )
        )
    }
}
