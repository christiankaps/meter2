import AppKit
import XCTest

@testable import Meter2

final class PDFReportTests: XCTestCase {
    func testPDFReportSelectedScopeIncludesOnlySelectedMeter() {
        let selected = Meter(name: "Kitchen", kind: .electricity)
        let other = Meter(name: "Bath", kind: .water)

        let snapshots = PDFReportGenerator.snapshots(
            meters: [selected, other],
            scope: .selectedMeter(selected.id),
            selectedPeriod: .currentMonth
        )

        XCTAssertEqual(snapshots.map(\.meterID), [selected.id])
    }

    func testPDFReportAllActiveScopeExcludesArchivedMeters() {
        let active = Meter(name: "Kitchen", kind: .electricity)
        let archived = Meter(name: "Old", kind: .custom, isArchived: true)

        let snapshots = PDFReportGenerator.snapshots(
            meters: [archived, active],
            scope: .allActiveMeters,
            selectedPeriod: .currentYear
        )

        XCTAssertEqual(snapshots.map(\.meterID), [active.id])
        XCTAssertEqual(snapshots.first?.period, .currentYear)
    }

    func testPDFReportSnapshotIncludesReadingStatisticsForecastAndCost() throws {
        let calendar = utcCalendar()
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let meter = Meter(name: "Kitchen", kind: .electricity, unit: "kWh", decimalPrecision: 1)
        meter.tariffs.append(MeterTariff(currencyCode: "EUR", unitPrice: 0.30, baseFee: 5, meter: meter))
        meter.readings.append(MeterReading(
            value: 100,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            recordedAtGranularity: .dateOnly,
            meter: meter
        ))
        meter.readings.append(MeterReading(
            value: 140,
            recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!,
            recordedAtGranularity: .dateOnly,
            note: "Manual",
            meter: meter
        ))

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            referenceDate: reference,
            calendar: calendar
        ).first)

        XCTAssertEqual(snapshot.latestReading?.value, 140)
        XCTAssertEqual(snapshot.readingCount, 2)
        XCTAssertNotNil(snapshot.statistics)
        XCTAssertNotNil(snapshot.statistics?.projectedCost)
        XCTAssertNotNil(snapshot.forecast)
        XCTAssertNotNil(snapshot.forecast?.projectedCost)
        XCTAssertEqual(snapshot.recentReadings.first?.note, "Manual")
    }

    func testPDFReportForecastUsesSelectedCurrentScopeOnly() throws {
        let calendar = utcCalendar()
        let reference = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!, meter: meter))
        meter.readings.append(MeterReading(value: 140, recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))!, meter: meter))

        let currentSnapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            referenceDate: reference,
            calendar: calendar
        ).first)
        let previousSnapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .previousMonths,
            referenceDate: reference,
            calendar: calendar
        ).first)

        XCTAssertNotNil(currentSnapshot.forecast)
        XCTAssertNil(previousSnapshot.forecast)
    }

    func testPDFReportSnapshotRepresentsInsufficientDataWithoutCrashing() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth
        ).first)

        XCTAssertNil(snapshot.statistics)
        XCTAssertNil(snapshot.forecast)
        XCTAssertEqual(snapshot.readingCount, 1)
    }

    func testPDFReportRecentReadingsAreNewestFirstAndCapped() throws {
        let calendar = utcCalendar()
        let meter = Meter(name: "Kitchen", kind: .electricity)
        for day in 1...25 {
            meter.readings.append(MeterReading(
                value: Double(day),
                recordedAt: calendar.date(from: DateComponents(year: 2026, month: 5, day: day))!,
                recordedAtGranularity: .dateOnly,
                meter: meter
            ))
        }

        let snapshot = try XCTUnwrap(PDFReportGenerator.snapshots(
            meters: [meter],
            scope: .selectedMeter(meter.id),
            selectedPeriod: .currentMonth,
            calendar: calendar
        ).first)

        XCTAssertEqual(snapshot.recentReadings.count, PDFReportGenerator.recentReadingLimit)
        XCTAssertEqual(snapshot.recentReadings.first?.value, 25)
        XCTAssertEqual(snapshot.recentReadings.last?.value, 6)
    }

    func testPDFReportSuggestedFileNamesAreSafe() {
        let meter = Meter(name: "Kitchen/Main", kind: .custom)

        XCTAssertEqual(PDFReportGenerator.suggestedFileName(for: .allActiveMeters, meters: [meter]), "meter2-report.pdf")
        XCTAssertEqual(PDFReportGenerator.suggestedFileName(for: .selectedMeter(meter.id), meters: [meter]), "meter2-Kitchen-Main-report.pdf")
    }

    func testPDFReportGeneratorCreatesNonEmptyPDFData() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)

        let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorCreatesValidEmptyAllActivePDF() throws {
        let data = try PDFReportGenerator.pdfData(snapshots: [], scope: .allActiveMeters)

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorHandlesVeryLongReadingNotes() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(
            value: 100,
            recordedAt: Date(timeIntervalSinceReferenceDate: 0),
            note: String(repeating: "Long note ", count: 500),
            meter: meter
        ))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)

        let data = try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }

    func testPDFReportGeneratorUsesPrintableColorsInDarkAppearance() throws {
        let meter = Meter(name: "Kitchen", kind: .electricity)
        meter.readings.append(MeterReading(value: 100, recordedAt: Date(timeIntervalSinceReferenceDate: 0), meter: meter))
        let snapshots = PDFReportGenerator.snapshots(meters: [meter], scope: .selectedMeter(meter.id), selectedPeriod: .currentMonth)
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var result: Result<Data, Error>?

        darkAppearance.performAsCurrentDrawingAppearance {
            result = Result {
                try PDFReportGenerator.pdfData(snapshots: snapshots, scope: .selectedMeter(meter.id))
            }
        }

        let data = try XCTUnwrap(result).get()

        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .utf8), "%PDF")
    }
}
