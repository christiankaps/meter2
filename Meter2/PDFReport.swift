import AppKit
import Foundation

enum ReportScope: Equatable {
    case selectedMeter(UUID)
    case allActiveMeters
}

struct MeterReadingSummary: Equatable {
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String
}

struct MeterReportSnapshot: Equatable {
    var meterID: UUID
    var meterName: String
    var meterKind: MeterKind
    var location: String
    var unit: String
    var currencyCode: String
    var decimalPrecision: Int
    var isArchived: Bool
    var period: StatisticsPeriod
    var generatedAt: Date
    var latestReading: MeterReadingSummary?
    var readingCount: Int
    var statistics: MeterStatisticsResult?
    var forecast: ForecastResult?
    var recentReadings: [MeterReadingSummary]
}

enum PDFReportGenerationError: LocalizedError {
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            String(localized: "report.error.invalidPDF")
        }
    }
}

enum PDFReportGenerator {
    static let recentReadingLimit = 20

    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 42

    static func snapshots(
        meters: [Meter],
        scope: ReportScope,
        selectedPeriod: StatisticsPeriod,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [MeterReportSnapshot] {
        let scopedMeters: [Meter]
        let period: StatisticsPeriod

        switch scope {
        case .selectedMeter(let id):
            scopedMeters = meters.filter { $0.id == id }
            period = selectedPeriod
        case .allActiveMeters:
            scopedMeters = meters.filter { !$0.isArchived }
            period = .month
        }

        return scopedMeters
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { meter in
                let recentReadings = meter.sortedReadingsDescending
                    .prefix(recentReadingLimit)
                    .map(readingSummary)
                let billingPeriod = meter.activeBillingPeriod.map { ($0.startsAt, $0.endsAt) }
                    ?? MeterAnalytics.defaultBillingPeriod(containing: referenceDate, calendar: calendar)

                return MeterReportSnapshot(
                    meterID: meter.id,
                    meterName: meter.name,
                    meterKind: meter.kind,
                    location: meter.location,
                    unit: meter.unit,
                    currencyCode: meter.activeTariff?.currencyCode ?? Locale.current.currency?.identifier ?? "EUR",
                    decimalPrecision: meter.decimalPrecision,
                    isArchived: meter.isArchived,
                    period: period,
                    generatedAt: referenceDate,
                    latestReading: meter.latestReading.map(readingSummary),
                    readingCount: meter.readings.count,
                    statistics: MeterAnalytics.statistics(
                        for: meter.readings,
                        period: period,
                        referenceDate: referenceDate,
                        tariff: meter.activeTariff,
                        calendar: calendar
                    ),
                    forecast: MeterAnalytics.forecast(
                        readings: meter.readings,
                        periodStart: billingPeriod.0,
                        periodEnd: billingPeriod.1,
                        tariff: meter.activeTariff,
                        referenceDate: referenceDate,
                        calendar: calendar
                    ),
                    recentReadings: Array(recentReadings)
                )
            }
    }

    static func suggestedFileName(for scope: ReportScope, meters: [Meter]) -> String {
        switch scope {
        case .allActiveMeters:
            "meter2-report.pdf"
        case .selectedMeter(let id):
            if let meter = meters.first(where: { $0.id == id }) {
                "meter2-\(safeFileNameComponent(meter.name))-report.pdf"
            } else {
                "meter2-report.pdf"
            }
        }
    }

    static func pdfData(
        snapshots: [MeterReportSnapshot],
        scope: ReportScope
    ) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFReportGenerationError.contextCreationFailed
        }

        var renderer = PDFReportRenderer(context: context, pageSize: pageSize, margin: margin)
        renderer.beginPage()
        renderer.drawTitle(title(for: scope, snapshots: snapshots))
        renderer.drawKeyValue(
            String(localized: "report.generatedAt"),
            MeterFormatting.mediumDateTime(snapshots.first?.generatedAt ?? Date())
        )

        if snapshots.isEmpty {
            renderer.drawSection(String(localized: "report.empty.title"))
            renderer.drawParagraph(String(localized: "report.empty.message"))
        } else {
            for snapshot in snapshots {
                renderer.drawSection(snapshot.meterName)
                drawSnapshot(snapshot, renderer: &renderer)
            }
        }

        renderer.finish()
        let pdfData = data as Data
        guard String(data: pdfData.prefix(4), encoding: .utf8) == "%PDF" else {
            throw PDFReportGenerationError.contextCreationFailed
        }
        return pdfData
    }

    private static func drawSnapshot(
        _ snapshot: MeterReportSnapshot,
        renderer: inout PDFReportRenderer
    ) {
        renderer.drawSubheading(String(localized: "report.meterDetails"))
        renderer.drawKeyValue(String(localized: "report.type"), snapshot.meterKind.localizedName)
        renderer.drawKeyValue(String(localized: "report.location"), snapshot.location.isEmpty ? unavailableText : snapshot.location)
        renderer.drawKeyValue(String(localized: "report.unit"), snapshot.unit)
        renderer.drawKeyValue(String(localized: "report.period"), snapshot.period.localizedName)
        renderer.drawKeyValue(String(localized: "report.readingCount"), "\(snapshot.readingCount)")

        if let latestReading = snapshot.latestReading {
            renderer.drawKeyValue(
                String(localized: "report.latestReading"),
                "\(formattedValue(latestReading.value, snapshot: snapshot)) · \(formattedDate(latestReading))"
            )
        } else {
            renderer.drawKeyValue(String(localized: "report.latestReading"), unavailableText)
        }

        renderer.drawSubheading(String(localized: "report.statistics"))
        if let statistics = snapshot.statistics {
            renderer.drawKeyValue(String(localized: "report.consumption"), formattedValue(statistics.consumption, snapshot: snapshot))
            renderer.drawKeyValue(
                String(localized: "report.averageDaily"),
                statistics.averageDailyConsumption.map { formattedValue($0, snapshot: snapshot) } ?? unavailableText
            )
            renderer.drawKeyValue(
                String(localized: "report.projectedConsumption"),
                statistics.projectedConsumption.map { formattedValue($0, snapshot: snapshot) } ?? unavailableText
            )
            renderer.drawKeyValue(
                String(localized: "report.projectionBasis"),
                statistics.projectionBasis.map { basis in
                    projectionBasisText(
                        basis: basis,
                        dayCount: statistics.projectionBasisDayCount,
                        readingCount: statistics.projectionBasisReadingCount
                    )
                } ?? unavailableText
            )
            renderer.drawKeyValue(
                String(localized: "report.projectionQuality"),
                statistics.projectionQuality?.localizedName ?? unavailableText
            )
            renderer.drawKeyValue(
                String(localized: "report.projectedCost"),
                statistics.projectedCost.map { MeterFormatting.currency($0, currencyCode: snapshot.currencyCode) } ?? unavailableText
            )
            renderer.drawKeyValue(
                String(localized: "report.previousComparison"),
                statistics.comparison.map(comparisonText) ?? statistics.comparisonUnavailableReason?.localizedText ?? unavailableText
            )
        } else {
            renderer.drawParagraph(String(localized: "report.insufficientData"))
        }

        renderer.drawSubheading(String(localized: "report.forecast"))
        if let forecast = snapshot.forecast {
            renderer.drawKeyValue(String(localized: "report.forecastConsumption"), formattedValue(forecast.projectedConsumption, snapshot: snapshot))
            renderer.drawKeyValue(String(localized: "report.forecastValue"), formattedValue(forecast.projectedValue, snapshot: snapshot))
            renderer.drawKeyValue(
                String(localized: "report.projectionBasis"),
                projectionBasisText(
                    basis: forecast.basis,
                    dayCount: forecast.basisDayCount,
                    readingCount: forecast.basisReadingCount
                )
            )
            renderer.drawKeyValue(String(localized: "report.projectionQuality"), forecast.quality.localizedName)
            renderer.drawKeyValue(
                String(localized: "report.forecastCost"),
                forecast.projectedCost.map { MeterFormatting.currency($0, currencyCode: snapshot.currencyCode) } ?? unavailableText
            )
        } else {
            renderer.drawParagraph(String(localized: "report.forecastUnavailable"))
        }

        renderer.drawSubheading(String(localized: "report.recentReadings"))
        if snapshot.recentReadings.isEmpty {
            renderer.drawParagraph(String(localized: "readings.empty.short"))
        } else {
            renderer.drawTableHeader([
                String(localized: "report.date"),
                String(localized: "report.value"),
                String(localized: "report.note")
            ])
            for reading in snapshot.recentReadings {
                renderer.drawTableRow([
                    formattedDate(reading),
                    formattedValue(reading.value, snapshot: snapshot),
                    reading.note
                ])
            }
        }
    }

    private static var unavailableText: String {
        String(localized: "report.notAvailable")
    }

    private static func readingSummary(_ reading: MeterReading) -> MeterReadingSummary {
        MeterReadingSummary(
            value: reading.value,
            recordedAt: reading.recordedAt,
            granularity: reading.recordedAtGranularity,
            note: reading.note
        )
    }

    private static func title(for scope: ReportScope, snapshots: [MeterReportSnapshot]) -> String {
        switch scope {
        case .selectedMeter:
            if let snapshot = snapshots.first {
                return String(localized: "report.title.selected \(snapshot.meterName)")
            }
            return String(localized: "report.title")
        case .allActiveMeters:
            return String(localized: "report.title.allActive")
        }
    }

    private static func formattedValue(_ value: Double, snapshot: MeterReportSnapshot) -> String {
        MeterFormatting.value(value, unit: snapshot.unit, precision: snapshot.decimalPrecision)
    }

    private static func formattedDate(_ reading: MeterReadingSummary) -> String {
        switch reading.granularity {
        case .dateOnly:
            MeterFormatting.shortDate(reading.recordedAt)
        case .dateTime:
            MeterFormatting.mediumDateTime(reading.recordedAt)
        }
    }

    private static func comparisonText(_ comparison: MeterPeriodComparison) -> String {
        let delta = MeterFormatting.decimal(comparison.absoluteDelta)
        guard let percent = comparison.percentageDelta else { return delta }
        return "\(delta) (\(MeterFormatting.signedPercent(percent)))"
    }

    private static func projectionBasisText(basis: ProjectionBasis, dayCount: Double?, readingCount: Int?) -> String {
        guard let dayCount, let readingCount else {
            return basis.localizedName
        }

        return String(localized: "projection.detail \(basis.localizedName) \(Int(dayCount.rounded())) \(readingCount)")
    }

    private static func safeFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return parts.isEmpty ? "meter" : parts
    }
}

private struct PDFReportRenderer {
    var context: CGContext
    let pageSize: CGSize
    let margin: CGFloat

    private let rowHeight: CGFloat = 18
    private var y: CGFloat = 0
    private var contentWidth: CGFloat {
        pageSize.width - margin * 2
    }

    init(context: CGContext, pageSize: CGSize, margin: CGFloat) {
        self.context = context
        self.pageSize = pageSize
        self.margin = margin
    }

    mutating func beginPage() {
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pageSize))
        context.saveGState()
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        y = margin
    }

    mutating func finish() {
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        context.endPDFPage()
        context.closePDF()
    }

    mutating func drawTitle(_ text: String) {
        drawText(text, font: .systemFont(ofSize: 22, weight: .semibold), spacingAfter: 12)
    }

    mutating func drawSection(_ text: String) {
        ensureSpace(54)
        y += 12
        drawText(text, font: .systemFont(ofSize: 17, weight: .semibold), spacingAfter: 8)
    }

    mutating func drawSubheading(_ text: String) {
        ensureSpace(42)
        y += 8
        drawText(text, font: .systemFont(ofSize: 12, weight: .semibold), color: .darkGray, spacingAfter: 4)
    }

    mutating func drawKeyValue(_ key: String, _ value: String) {
        let keyWidth = contentWidth * 0.34
        let valueWidth = contentWidth * 0.62
        let keyText = attributed(key, font: .systemFont(ofSize: 10, weight: .medium), color: .darkGray)
        let valueText = attributed(displayText(value.isEmpty ? " " : value), font: .systemFont(ofSize: 10), color: .black)
        let height = max(
            rowHeight,
            textHeight(keyText, width: keyWidth),
            textHeight(valueText, width: valueWidth)
        )
        ensureSpace(height)
        keyText.draw(in: CGRect(x: margin, y: y, width: keyWidth, height: height))
        valueText.draw(in: CGRect(x: margin + contentWidth * 0.38, y: y, width: valueWidth, height: height))
        y += height
    }

    mutating func drawParagraph(_ text: String) {
        drawText(text, font: .systemFont(ofSize: 10), color: .darkGray, spacingAfter: 6)
    }

    mutating func drawTableHeader(_ values: [String]) {
        ensureSpace(rowHeight)
        drawTable(values, font: .systemFont(ofSize: 9, weight: .semibold), color: .darkGray)
    }

    mutating func drawTableRow(_ values: [String]) {
        ensureSpace(rowHeight)
        drawTable(values, font: .systemFont(ofSize: 9), color: .black)
    }

    private mutating func drawText(
        _ text: String,
        font: NSFont,
        color: NSColor = .black,
        spacingAfter: CGFloat
    ) {
        let attributedText = attributed(text, font: font, color: color)
        let height = ceil(attributedText.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).height)
        ensureSpace(height + spacingAfter)
        attributedText.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height + 2))
        y += height + spacingAfter
    }

    private mutating func drawTable(_ values: [String], font: NSFont, color: NSColor) {
        let widths = [contentWidth * 0.28, contentWidth * 0.24, contentWidth * 0.48]
        let texts = values.prefix(widths.count).map { attributed(displayText($0), font: font, color: color) }
        let height = max(rowHeight, zip(texts, widths).map { textHeight($0.0, width: $0.1 - 8) }.max() ?? rowHeight)
        ensureSpace(height)
        var x = margin
        for index in 0..<texts.count {
            texts[index].draw(in: CGRect(x: x, y: y, width: widths[index] - 8, height: height))
            x += widths[index]
        }
        y += height
    }

    private mutating func ensureSpace(_ height: CGFloat) {
        guard y + height > pageSize.height - margin else { return }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        context.endPDFPage()
        beginPage()
    }

    private func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
    }

    private func textHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin]
        ).height) + 2
    }

    private func displayText(_ text: String) -> String {
        let maxCharacters = 600
        guard text.count > maxCharacters else { return text }
        return "\(text.prefix(maxCharacters))..."
    }
}
