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
        let schema = Schema([Meter.self, MeterReading.self, MeterTariff.self, BillingPeriod.self])
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
            "accessibility.reading.addForMeter %@",
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
