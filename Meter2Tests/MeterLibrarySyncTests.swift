import XCTest

@testable import Meter2

private final class InMemoryMeterLibrarySyncStateStore: MeterLibrarySyncStateStore {
    private var state: MeterLibrarySyncState?

    func loadState() -> MeterLibrarySyncState? {
        state
    }

    func saveState(_ state: MeterLibrarySyncState) {
        self.state = state
    }
}

final class MeterLibrarySyncTests: XCTestCase {
    @MainActor
    func testSyncEnableQueuesWholeLibraryForOptInMigration() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        let reading = MeterReading(value: 42, recordedAt: Date(timeIntervalSinceReferenceDate: 100), meter: meter)
        let tariff = MeterTariff(currencyCode: "EUR", unitPrice: 0.3, baseFee: 4, meter: meter)
        let period = BillingPeriod(
            startsAt: Date(timeIntervalSinceReferenceDate: 0),
            endsAt: Date(timeIntervalSinceReferenceDate: 86_400),
            label: "May",
            meter: meter
        )
        meter.readings.append(reading)
        meter.tariffs.append(tariff)
        meter.billingPeriods.append(period)
        let syncService = MeterLibrarySyncService(stateStore: InMemoryMeterLibrarySyncStateStore())

        try syncService.enableSync(for: [meter], libraryID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)

        XCTAssertEqual(syncService.status, .idle)
        XCTAssertEqual(syncService.currentRole, .owner)
        XCTAssertEqual(syncService.pendingOperations.count, 4)
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertMeter(MeterSyncRecord(meter: meter))))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertTariff(MeterTariffSyncRecord(tariff: tariff)!)))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertBillingPeriod(BillingPeriodSyncRecord(period: period)!)))
        XCTAssertTrue(syncService.pendingOperations.contains(.upsertReading(MeterReadingSyncRecord(reading: reading)!)))
    }

    @MainActor
    func testCollaboratorCanOnlyQueueReadingChanges() throws {
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .collaborator,
            libraryID: UUID()
        )

        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            meterID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            value: 12,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        try syncService.enqueue(.upsertReading(readingRecord))

        XCTAssertThrowsError(try syncService.enqueue(.deleteMeter(UUID()))) { error in
            XCTAssertEqual(error as? MeterLibrarySyncError, .permissionDenied(.deleteMeter))
        }
    }

    @MainActor
    func testSyncMergeKeepsLatestReadingEdit() {
        let readingID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let meterID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let local = MeterReadingSyncRecord(
            id: readingID,
            meterID: meterID,
            value: 10,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "Local",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let remote = MeterReadingSyncRecord(
            id: readingID,
            meterID: meterID,
            value: 11,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "Remote",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )

        let merged = MeterLibrarySyncService.mergeReadings(local: [local], remote: [remote])

        XCTAssertEqual(merged, [remote])
    }

    @MainActor
    func testSyncNowKeepsPendingOperationsUntilDurableCloudHandoffExists() throws {
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .owner,
            libraryID: UUID()
        )
        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            meterID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            value: 21,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        try syncService.enqueue(.upsertReading(readingRecord))

        let result = try syncService.syncNow()

        XCTAssertEqual(result.acceptedOperations, [.upsertReading(readingRecord)])
        XCTAssertEqual(syncService.pendingOperations, [.upsertReading(readingRecord)])
    }

    @MainActor
    func testCollaboratorSyncAcceptsOwnerLibraryChangesButRejectsCollaboratorAdminChanges() throws {
        let meter = Meter(name: "Shared", kind: .water)
        let syncService = MeterLibrarySyncService(
            stateStore: InMemoryMeterLibrarySyncStateStore(),
            status: .idle,
            currentRole: .collaborator,
            libraryID: UUID()
        )
        let ownerOperation = MeterRemoteSyncOperation.verifiedOwnerChange(.upsertMeter(MeterSyncRecord(meter: meter)))
        let collaboratorOperation = MeterRemoteSyncOperation.verifiedCollaboratorChange(.deleteMeter(meter.id))

        let result = try syncService.syncNow(remoteOperations: [ownerOperation, collaboratorOperation])

        XCTAssertEqual(result.acceptedOperations, [ownerOperation.operation])
        XCTAssertEqual(result.rejectedOperations, [collaboratorOperation.operation])
    }

    @MainActor
    func testSyncServiceRestoresPersistedStateAndPendingOperations() throws {
        let store = InMemoryMeterLibrarySyncStateStore()
        let libraryID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let readingRecord = MeterReadingSyncRecord(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            meterID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            value: 31,
            recordedAt: Date(timeIntervalSinceReferenceDate: 100),
            granularity: .dateTime,
            note: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        store.saveState(
            MeterLibrarySyncState(
                status: .idle,
                currentRole: .collaborator,
                libraryID: libraryID,
                pendingOperations: [.upsertReading(readingRecord)]
            )
        )

        let syncService = MeterLibrarySyncService(stateStore: store)

        XCTAssertEqual(syncService.status, .idle)
        XCTAssertEqual(syncService.currentRole, .collaborator)
        XCTAssertEqual(syncService.libraryID, libraryID)
        XCTAssertEqual(syncService.pendingOperations, [.upsertReading(readingRecord)])
    }
}
