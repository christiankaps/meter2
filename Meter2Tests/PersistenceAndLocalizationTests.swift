import SwiftData
import XCTest

@testable import Meter2

final class PersistenceAndLocalizationTests: XCTestCase {
    private enum SaveError: Error {
        case failed
    }

    private final class PersistenceContextStub: PersistenceContextCommitting {
        var saveError: Error?
        private(set) var saveCallCount = 0
        private(set) var rollbackCallCount = 0

        func save() throws {
            saveCallCount += 1
            if let saveError {
                throw saveError
            }
        }

        func rollback() {
            rollbackCallCount += 1
        }
    }

    func testPersistenceCommitterSavesSuccessfulChangesWithoutRollback() {
        let context = PersistenceContextStub()
        var didApplyChanges = false

        let result = PersistenceCommitter.commit(using: context) {
            didApplyChanges = true
        }

        XCTAssertTrue(didApplyChanges)
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(context.saveCallCount, 1)
        XCTAssertEqual(context.rollbackCallCount, 0)
    }

    func testPersistenceCommitterRollsBackWhenSaveFails() {
        let context = PersistenceContextStub()
        context.saveError = SaveError.failed

        let result = PersistenceCommitter.commit(using: context) {}

        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is SaveError)
        }
        XCTAssertEqual(context.saveCallCount, 1)
        XCTAssertEqual(context.rollbackCallCount, 1)
    }

    func testSwiftDataPersistsMeterReadingArchiveAndCascadeDelete() throws {
        let schema = Schema([Meter.self, MeterReading.self, MeterTariff.self, BillingPeriod.self, VirtualMeterTerm.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let meter = Meter(name: "Main", kind: .electricity)
        context.insert(meter)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(), meter: meter))
        try context.save()

        var meterFetch = FetchDescriptor<Meter>()
        meterFetch.includePendingChanges = true
        XCTAssertEqual(try context.fetch(meterFetch).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeterReading>()).count, 1)

        meter.isArchived = true
        try context.save()
        XCTAssertTrue(try XCTUnwrap(context.fetch(meterFetch).first).isArchived)

        context.delete(meter)
        try context.save()
        XCTAssertEqual(try context.fetch(meterFetch).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeterReading>()).count, 0)
    }

    func testExampleDataIsStableCompleteAndIdempotent() throws {
        let calendar = utcCalendar()
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))
        )
        let meters = ExampleData.makeMeters(referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(Set(meters.map(\.id)), ExampleData.meterIDs)
        XCTAssertEqual(meters.count, 3)
        XCTAssertTrue(meters.allSatisfy { $0.readings.count == 13 })
        XCTAssertTrue(meters.allSatisfy { meter in
            zip(meter.sortedReadingsAscending, meter.sortedReadingsAscending.dropFirst())
                .allSatisfy { pair in
                    pair.0.recordedAt < pair.1.recordedAt && pair.0.value < pair.1.value
                }
        })
        XCTAssertTrue(
            ExampleData.makeMissingMeters(
                existingMeterIDs: ExampleData.meterIDs,
                referenceDate: referenceDate,
                calendar: calendar
            ).isEmpty
        )

        let oneExistingID = try XCTUnwrap(meters.first?.id)
        let missing = ExampleData.makeMissingMeters(
            existingMeterIDs: [oneExistingID],
            referenceDate: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(missing.count, 2)
        XCTAssertFalse(missing.contains { $0.id == oneExistingID })
    }

    func testExampleDataRestoreUsesSurvivingTimeline() throws {
        let calendar = utcCalendar()
        let initialReferenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 10))
        )
        let laterFallbackDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))
        )
        let existingMeters = Array(
            ExampleData.makeMeters(referenceDate: initialReferenceDate, calendar: calendar).dropFirst()
        )

        let restoreReferenceDate = ExampleData.referenceDate(
            for: existingMeters,
            fallback: laterFallbackDate
        )
        let restoredMeters = ExampleData.makeMissingMeters(
            existingMeterIDs: Set(existingMeters.map(\.id)),
            referenceDate: restoreReferenceDate,
            calendar: calendar
        )

        XCTAssertEqual(restoreReferenceDate, initialReferenceDate)
        XCTAssertEqual(restoredMeters.count, 1)
        XCTAssertEqual(restoredMeters.first?.latestReading?.recordedAt, initialReferenceDate)
    }

    func testExampleGasUsageIsHigherInWinterThanSummer() throws {
        let calendar = utcCalendar()
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 12, day: 10))
        )
        let gasMeter = try XCTUnwrap(
            ExampleData.makeMeters(referenceDate: referenceDate, calendar: calendar)
                .first { $0.kind == .gas }
        )
        let readings = gasMeter.sortedReadingsAscending
        let monthlyUsage = Dictionary(uniqueKeysWithValues: zip(readings, readings.dropFirst()).map { pair in
            let month = calendar.component(.month, from: pair.1.recordedAt)
            return (month, pair.1.value - pair.0.value)
        })

        XCTAssertGreaterThan(try XCTUnwrap(monthlyUsage[1]), try XCTUnwrap(monthlyUsage[7]))
        XCTAssertGreaterThan(try XCTUnwrap(monthlyUsage[12]), try XCTUnwrap(monthlyUsage[8]))
    }

    func testDeletingExampleDataPreservesUserMeters() throws {
        let schema = Schema([Meter.self, MeterReading.self, MeterTariff.self, BillingPeriod.self, VirtualMeterTerm.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let userMeter = Meter(name: "User Meter", kind: .electricity)

        context.insert(userMeter)
        for meter in ExampleData.makeMeters() {
            context.insert(meter)
        }
        try context.save()

        for meter in try context.fetch(FetchDescriptor<Meter>()).filter(ExampleData.isExampleMeter) {
            context.delete(meter)
        }
        try context.save()

        let remainingMeters = try context.fetch(FetchDescriptor<Meter>())
        XCTAssertEqual(remainingMeters.map(\.id), [userMeter.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MeterReading>()).count, 0)
    }

    func testVirtualMeterFormulaPersistsAndDeletingItPreservesSource() throws {
        let schema = Schema([Meter.self, MeterReading.self, MeterTariff.self, BillingPeriod.self, VirtualMeterTerm.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let source = Meter(name: "Solar", kind: .solar, unit: "kWh")
        let virtual = Meter(name: "Self-consumption", kind: .electricity, unit: "kWh")
        virtual.dataSourceKind = .virtual
        let term = VirtualMeterTerm(operation: .add, displayOrder: 0, owner: virtual, source: source)
        virtual.virtualTerms.append(term)
        context.insert(source)
        context.insert(virtual)
        try context.save()

        XCTAssertEqual(virtual.sortedVirtualTerms.count, 1)
        XCTAssertEqual(source.dependentVirtualTerms.first?.owner?.id, virtual.id)
        XCTAssertEqual(source.dependentVirtualMeterNames, ["Self-consumption"])

        context.delete(virtual)
        try context.save()

        let remainingMeters = try context.fetch(FetchDescriptor<Meter>())
        XCTAssertEqual(remainingMeters.map(\.id), [source.id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<VirtualMeterTerm>()).isEmpty)
    }

    func testLocalizationCatalogContainsEnglishAndGermanEntries() throws {
        let appBundle = try XCTUnwrap(
            Bundle.allBundles.first { $0.bundleIdentifier == AppConfiguration.bundleIdentifier }
        )
        XCTAssertNotNil(appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        XCTAssertNotNil(appBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "de"))

        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        let reportKeys = [
            "report.menu",
            "report.export.selected",
            "report.print.selected",
            "report.export.allActive",
            "report.print.allActive",
            "report.progress.generating",
            "report.insufficientData",
            "report.forecastUnavailable"
        ]
        for key in reportKeys {
            XCTAssertNotNil(strings[key], "Missing report localization key \(key)")
        }
        let updateKeys = [
            "about.menu",
            "about.title",
            "update.check",
            "update.install",
            "update.releasePage",
            "update.status.checking",
            "update.error.missingInstallerAsset"
        ]
        for key in updateKeys {
            XCTAssertNotNil(strings[key], "Missing update localization key \(key)")
        }
        let uxConsistencyKeys = [
            "help.shortcut.key.addMeter",
            "help.shortcut.key.addReading",
            "help.shortcut.key.importCSV",
            "help.shortcut.key.exportCSV",
            "help.shortcut.key.help",
            "reading.saveAndNext",
            "save"
        ]
        for key in uxConsistencyKeys {
            XCTAssertNotNil(strings[key], "Missing UX consistency localization key \(key)")
        }
        let persistenceKeys = [
            "persistence.error.title",
            "persistence.error.message %@"
        ]
        for key in persistenceKeys {
            XCTAssertNotNil(strings[key], "Missing persistence localization key \(key)")
        }
        let exampleDataKeys = [
            "exampleData.load",
            "exampleData.delete",
            "exampleData.delete.confirm.title",
            "exampleData.delete.confirm.message",
            "exampleData.electricity.name",
            "exampleData.water.name",
            "exampleData.gas.name"
        ]
        for key in exampleDataKeys {
            XCTAssertNotNil(strings[key], "Missing example data localization key \(key)")
        }
        let virtualMeterKeys = [
            "meter.source.manual",
            "meter.source.virtual",
            "virtualMeter.term.add",
            "virtualMeter.validation.formula",
            "virtualMeter.delete.blocked.title",
            "virtualMeter.delete.blocked.message %@"
        ]
        for key in virtualMeterKeys {
            XCTAssertNotNil(strings[key], "Missing virtual meter localization key \(key)")
        }

        for key in strings.keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            XCTAssertNotEqual(
                entry["extractionState"] as? String,
                "stale",
                "Stale localization entry for \(key)"
            )
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "de"] {
                let localization = try XCTUnwrap(
                    localizations[locale] as? [String: Any],
                    "Missing \(locale) localization for \(key)"
                )
                let stringUnit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any],
                    "Missing \(locale) string unit for \(key)"
                )
                XCTAssertEqual(
                    stringUnit["state"] as? String,
                    "translated",
                    "Unexpected \(locale) localization state for \(key)"
                )
                let value = try XCTUnwrap(
                    stringUnit["value"] as? String,
                    "Missing \(locale) localized value for \(key)"
                )
                XCTAssertFalse(value.isEmpty, "Empty \(locale) localized value for \(key)")
            }
        }
    }
}
