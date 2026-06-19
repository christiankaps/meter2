import Foundation

struct CSVDocument: Equatable, Sendable {
    var headers: [String]
    var rows: [[String]]
    var delimiter: Character
}

enum CSVExportScope: Equatable {
    case allReadings
    case meter(UUID)
}

struct CSVExportRecord {
    var meterName: String
    var value: Double
    var unit: String
    var note: String
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var readingID: UUID
}

enum CSVExporter {
    private struct ExportEntry {
        var meter: Meter
        var reading: MeterReading
    }

    static func export(meters: [Meter], scope: CSVExportScope, calendar: Calendar = .current) -> String {
        let entries = exportEntries(meters: meters, scope: scope)
        let rows = [["Date", "Meter", "Value", "Unit", "Note"]]
            + entries.map { entry in
                [
                    formattedDate(entry.reading, calendar: calendar),
                    spreadsheetSafeText(entry.meter.name),
                    String(entry.reading.value),
                    spreadsheetSafeText(entry.meter.unit),
                    spreadsheetSafeText(entry.reading.note)
                ]
            }

        return rows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    static func export(records: [CSVExportRecord], calendar: Calendar = .current) -> String {
        let rows = [["Date", "Meter", "Value", "Unit", "Note"]]
            + records
            .sorted { lhs, rhs in
                if lhs.recordedAt != rhs.recordedAt {
                    return lhs.recordedAt < rhs.recordedAt
                }
                if lhs.meterName != rhs.meterName {
                    return lhs.meterName.localizedStandardCompare(rhs.meterName) == .orderedAscending
                }
                return lhs.readingID.uuidString < rhs.readingID.uuidString
            }
            .map { record in
                [
                    formattedDate(recordedAt: record.recordedAt, granularity: record.granularity, calendar: calendar),
                    spreadsheetSafeText(record.meterName),
                    String(record.value),
                    spreadsheetSafeText(record.unit),
                    spreadsheetSafeText(record.note)
                ]
            }

        return rows
            .map { $0.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    static func suggestedFileName(for scope: CSVExportScope, meters: [Meter]) -> String {
        switch scope {
        case .allReadings:
            "meter2-readings.csv"
        case .meter(let id):
            if let meter = meters.first(where: { $0.id == id }) {
                "meter2-\(safeFileNameComponent(meter.name))-readings.csv"
            } else {
                "meter2-readings.csv"
            }
        }
    }

    static func formattedDate(_ reading: MeterReading, calendar: Calendar = .current) -> String {
        formattedDate(
            recordedAt: reading.recordedAt,
            granularity: reading.recordedAtGranularity,
            calendar: calendar
        )
    }

    static func formattedDate(
        recordedAt: Date,
        granularity: ReadingTimestampGranularity,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = granularity == .dateOnly ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: recordedAt)
    }

    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func spreadsheetSafeText(_ field: String) -> String {
        guard startsFormulaAfterLeadingApostrophes(field) else {
            return field
        }

        return "'\(field)"
    }

    private static func exportEntries(meters: [Meter], scope: CSVExportScope) -> [ExportEntry] {
        let filteredMeters: [Meter]
        switch scope {
        case .allReadings:
            filteredMeters = meters
        case .meter(let id):
            filteredMeters = meters.filter { $0.id == id }
        }

        return filteredMeters
            .flatMap { meter in meter.readings.map { ExportEntry(meter: meter, reading: $0) } }
            .sorted { lhs, rhs in
                if lhs.reading.recordedAt != rhs.reading.recordedAt {
                    return lhs.reading.recordedAt < rhs.reading.recordedAt
                }
                if lhs.meter.name != rhs.meter.name {
                    return lhs.meter.name.localizedStandardCompare(rhs.meter.name) == .orderedAscending
                }
                return lhs.reading.id.uuidString < rhs.reading.id.uuidString
            }
    }

    private static func safeFileNameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return parts.isEmpty ? "meter" : parts
    }

    private static func startsFormulaAfterLeadingApostrophes(_ field: String) -> Bool {
        var remainder = field[...]
        while remainder.first == "'" {
            remainder = remainder.dropFirst()
        }
        while let first = remainder.first, first == " " || first == "\t" {
            remainder = remainder.dropFirst()
        }

        guard let first = remainder.first else { return false }
        return ["=", "+", "-", "@"].contains(first)
    }
}

enum CSVNumberParser {
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        if trimmedText.contains("."), !trimmedText.contains(","), let value = Double(trimmedText), value.isFinite {
            return value
        }

        if let value = ReadingValueParser.parse(trimmedText, locale: locale) {
            return value
        }

        guard trimmedText.contains(","), !trimmedText.contains(".") else { return nil }

        let normalizedText = trimmedText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalizedText), value.isFinite else { return nil }
        return value
    }
}

enum CSVSpreadsheetSafety {
    static func restoredText(_ field: String) -> String {
        guard field.first == "'",
              startsFormulaAfterLeadingApostrophes(String(field.dropFirst())) else {
            return field
        }

        return String(field.dropFirst())
    }

    private static func startsFormulaAfterLeadingApostrophes(_ field: String) -> Bool {
        var remainder = field[...]
        while remainder.first == "'" {
            remainder = remainder.dropFirst()
        }
        while let first = remainder.first, first == " " || first == "\t" {
            remainder = remainder.dropFirst()
        }

        guard let first = remainder.first else { return false }
        return ["=", "+", "-", "@"].contains(first)
    }
}

enum CSVParserError: LocalizedError, Equatable {
    case emptyDocument
    case unclosedQuote
    case missingHeaders

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            String(localized: "csv.importError.emptyDocument")
        case .unclosedQuote:
            String(localized: "csv.importError.unclosedQuote")
        case .missingHeaders:
            String(localized: "csv.importError.missingHeaders")
        }
    }
}

enum CSVParser {
    static func parse(_ text: String) throws -> CSVDocument {
        let delimiter = detectDelimiter(in: text)
        let parsedRows = try parseRows(text, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

        guard let headers = parsedRows.first else { throw CSVParserError.emptyDocument }
        let trimmedHeaders = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmedHeaders.contains(where: { !$0.isEmpty }) else { throw CSVParserError.missingHeaders }

        return CSVDocument(
            headers: trimmedHeaders,
            rows: parsedRows.dropFirst().map { normalizedRow($0, width: trimmedHeaders.count) },
            delimiter: delimiter
        )
    }

    private static func detectDelimiter(in text: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        func score(for candidate: Character) -> Int {
            guard let firstRow = try? parseRows(text, delimiter: candidate).first else { return 0 }
            return firstRow.count
        }

        return candidates.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        } ?? ","
    }

    private static func parseRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isInsideQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            isInsideQuotes = false
                            if next == delimiter {
                                row.append(field)
                                field = ""
                            } else if next.isNewline {
                                row.append(field)
                                rows.append(row)
                                row = []
                                field = ""
                            } else {
                                field.append(next)
                            }
                        }
                    } else {
                        isInsideQuotes = false
                    }
                } else if field.isEmpty {
                    isInsideQuotes = true
                } else {
                    field.append(character)
                }
            } else if character == delimiter, !isInsideQuotes {
                row.append(field)
                field = ""
            } else if character.isNewline, !isInsideQuotes {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }

        guard !isInsideQuotes else { throw CSVParserError.unclosedQuote }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func normalizedRow(_ row: [String], width: Int) -> [String] {
        if row.count >= width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }
}

struct CSVParsedDate: Equatable {
    var date: Date
    var granularity: ReadingTimestampGranularity
}

enum CSVDateParser {
    static func parse(_ text: String, calendar: Calendar = .current) -> CSVParsedDate? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        for format in dateTimeFormats {
            if let date = formatter(format: format, calendar: calendar).date(from: value) {
                return CSVParsedDate(date: MeterAnalytics.normalizedToDisplayedMinute(date, calendar: calendar), granularity: .dateTime)
            }
        }

        for format in dateOnlyFormats {
            if let date = formatter(format: format, calendar: calendar).date(from: value) {
                return CSVParsedDate(date: calendar.startOfDay(for: date), granularity: .dateOnly)
            }
        }

        return nil
    }

    private static let dateOnlyFormats = [
        "ddMMyyyy",
        "yyyyMMdd",
        "yyyy-MM-dd",
        "dd.MM.yyyy",
        "MM/dd/yyyy",
        "yyyy/MM/dd"
    ]

    private static let dateTimeFormats = [
        "ddMMyyyy HHmm",
        "ddMMyyyy HH:mm",
        "yyyyMMdd HHmm",
        "yyyyMMdd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "dd.MM.yyyy HH:mm:ss",
        "dd.MM.yyyy HH:mm",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm"
    ]

    private static func formatter(format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

enum CSVImportShape: String, CaseIterable, Identifiable, Sendable {
    case wide
    case long

    var id: String { rawValue }
}

struct CSVNewMeterDraft: Equatable, Sendable {
    var key: String
    var name: String
    var unit: String
    var location: String = ""
    var decimalPrecision: Int = 1

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum CSVImportMeterTarget: Equatable, Sendable {
    case ignore
    case existing(UUID)
    case new(CSVNewMeterDraft)
}

struct CSVWideValueMapping: Equatable, Identifiable, Sendable {
    var id: Int { columnIndex }
    var columnIndex: Int
    var target: CSVImportMeterTarget
}

struct CSVColumnMapping: Equatable, Sendable {
    var shape: CSVImportShape
    var dateColumnIndex: Int
    var noteColumnIndex: Int?
    var meterColumnIndex: Int?
    var valueColumnIndex: Int?
    var unitColumnIndex: Int?
    var wideValueMappings: [CSVWideValueMapping] = []
    var longCreateMissingMeters: Bool = true
    var longNewMeterDrafts: [String: CSVNewMeterDraft] = [:]
}

enum CSVImportPreviewStatus: String, Equatable, Sendable {
    case valid
    case duplicate
    case skipped
    case invalid
}

enum CSVImportPreviewMessage: String, Equatable, Sendable {
    case ready
    case duplicate
    case emptyValue
    case ignored
    case invalidDate
    case invalidValue
    case missingMapping
    case missingMeterSetup

    var localizedText: String {
        switch self {
        case .ready:
            String(localized: "csv.message.ready")
        case .duplicate:
            String(localized: "csv.message.duplicate")
        case .emptyValue:
            String(localized: "csv.message.emptyValue")
        case .ignored:
            String(localized: "csv.message.ignored")
        case .invalidDate:
            String(localized: "csv.message.invalidDate")
        case .invalidValue:
            String(localized: "csv.message.invalidValue")
        case .missingMapping:
            String(localized: "csv.message.missingMapping")
        case .missingMeterSetup:
            String(localized: "csv.message.missingMeterSetup")
        }
    }
}

enum CSVImportMeterReference: Hashable, Equatable, Sendable {
    case existing(UUID)
    case new(String)
}

struct CSVPlannedReading: Equatable, Sendable {
    var rowNumber: Int
    var meterReference: CSVImportMeterReference
    var newMeterDraft: CSVNewMeterDraft?
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String
}

struct CSVImportPreviewRow: Identifiable, Equatable, Sendable {
    var id = UUID()
    var rowNumber: Int
    var meterName: String
    var valueText: String
    var dateText: String
    var status: CSVImportPreviewStatus
    var message: CSVImportPreviewMessage
    var plannedReading: CSVPlannedReading?
}

struct CSVImportResult: Equatable, Sendable {
    var createdMeters: Int
    var importedReadings: Int
    var skippedDuplicates: Int
    var skippedInvalidRows: Int
}

struct CSVImportMeterSnapshot: Equatable, Sendable {
    struct Reading: Equatable, Sendable {
        var recordedAt: Date
        var granularity: ReadingTimestampGranularity
    }

    var id: UUID
    var name: String
    var readings: [Reading]

    init(meter: Meter) {
        id = meter.id
        name = meter.name
        readings = meter.readings.map {
            Reading(recordedAt: $0.recordedAt, granularity: $0.recordedAtGranularity)
        }
    }
}

struct CSVImportPreviewPayload: Equatable, Sendable {
    var mapping: CSVColumnMapping
    var rows: [CSVImportPreviewRow]
    var result: CSVImportResult
    var missingLongMeterDrafts: [CSVNewMeterDraft]
}

enum CSVImportPlanner {
    static func suggestedMapping(for document: CSVDocument, existingMeters: [Meter]) -> CSVColumnMapping {
        let dateIndex = bestHeaderIndex(in: document.headers, names: ["date", "datum", "recorded", "recorded at", "timestamp"]) ?? 0
        let noteIndex = bestHeaderIndex(in: document.headers, names: ["note", "notes", "notiz", "bemerkung"])
        let meterIndex = bestHeaderIndex(in: document.headers, names: ["meter", "meter name", "name", "metername", "zähler", "zaehler", "zählername", "zaehlername"])
        let valueIndex = bestHeaderIndex(in: document.headers, names: ["value", "wert", "reading", "reading value", "stand", "zählerstand", "zaehlerstand"])
        let unitIndex = bestHeaderIndex(in: document.headers, names: ["unit", "einheit"])
        let shape: CSVImportShape = isLongMapping(
            dateIndex: dateIndex,
            meterIndex: meterIndex,
            valueIndex: valueIndex
        ) ? .long : .wide

        var existingByName: [String: UUID] = [:]
        for meter in existingMeters {
            let key = normalizedLookupKey(meter.name)
            if existingByName[key] == nil {
                existingByName[key] = meter.id
            }
        }
        let wideMappings = document.headers.enumerated()
            .filter { index, _ in
                index != dateIndex
                    && index != noteIndex
                    && (shape != .long || (index != meterIndex && index != valueIndex && index != unitIndex))
            }
            .map { index, header in
                let target: CSVImportMeterTarget
                if let meterID = existingByName[normalizedLookupKey(header)] {
                    target = .existing(meterID)
                } else {
                    target = .new(CSVNewMeterDraft(key: "wide:\(index):\(header)", name: header, unit: ""))
                }
                return CSVWideValueMapping(columnIndex: index, target: target)
            }

        return CSVColumnMapping(
            shape: shape,
            dateColumnIndex: dateIndex,
            noteColumnIndex: noteIndex,
            meterColumnIndex: meterIndex,
            valueColumnIndex: valueIndex,
            unitColumnIndex: unitIndex,
            wideValueMappings: wideMappings
        )
    }

    static func preview(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [Meter],
        calendar: Calendar = .current
    ) -> [CSVImportPreviewRow] {
        preview(
            document: document,
            mapping: mapping,
            existingMeters: existingMeters.map(CSVImportMeterSnapshot.init),
            calendar: calendar
        )
    }

    static func previewPayload(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot],
        calendar: Calendar = .current
    ) throws -> CSVImportPreviewPayload {
        let missingLongMeterDrafts = try missingLongMeterDrafts(
            document: document,
            mapping: mapping,
            existingMeters: existingMeters
        )
        var resolvedMapping = mapping
        resolvedMapping.longNewMeterDrafts = Dictionary(uniqueKeysWithValues: missingLongMeterDrafts.map { draft in
            (draft.key, mapping.longNewMeterDrafts[draft.key] ?? draft)
        })
        let rows = try preview(
            document: document,
            mapping: resolvedMapping,
            existingMeters: existingMeters,
            calendar: calendar,
            cancellationCheck: { try Task.checkCancellation() }
        )

        return CSVImportPreviewPayload(
            mapping: resolvedMapping,
            rows: rows,
            result: result(from: rows),
            missingLongMeterDrafts: missingLongMeterDrafts
        )
    }

    private static func preview(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot],
        calendar: Calendar = .current
    ) -> [CSVImportPreviewRow] {
        preview(
            document: document,
            mapping: mapping,
            existingMeters: existingMeters,
            calendar: calendar,
            cancellationCheck: {}
        )
    }

    private static func preview(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot],
        calendar: Calendar,
        cancellationCheck: () throws -> Void
    ) rethrows -> [CSVImportPreviewRow] {
        var rows: [CSVImportPreviewRow] = []
        var seenReadings: [CSVPlannedReading] = []

        for (rowIndex, row) in document.rows.enumerated() {
            try cancellationCheck()
            let rowNumber = rowIndex + 2
            switch mapping.shape {
            case .wide:
                rows.append(contentsOf: previewWideRow(
                    row,
                    rowNumber: rowNumber,
                    mapping: mapping,
                    existingMeters: existingMeters,
                    seenReadings: &seenReadings,
                    calendar: calendar
                ))
            case .long:
                rows.append(previewLongRow(
                    row,
                    rowNumber: rowNumber,
                    mapping: mapping,
                    existingMeters: existingMeters,
                    seenReadings: &seenReadings,
                    calendar: calendar
                ))
            }
        }

        return rows
    }

    private static func missingLongMeterDrafts(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot]
    ) throws -> [CSVNewMeterDraft] {
        guard mapping.shape == .long,
              let meterColumnIndex = mapping.meterColumnIndex,
              document.headers.indices.contains(meterColumnIndex) else {
            return []
        }

        let existingNames = Set(existingMeters.map { normalizedLookupKey($0.name) })
        var draftsByKey: [String: CSVNewMeterDraft] = [:]

        for row in document.rows {
            try Task.checkCancellation()
            let meterName = CSVSpreadsheetSafety.restoredText(
                value(in: row, at: meterColumnIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !meterName.isEmpty, !existingNames.contains(normalizedLookupKey(meterName)) else {
                continue
            }

            let unit = mapping.unitColumnIndex.map {
                CSVSpreadsheetSafety.restoredText(value(in: row, at: $0))
            } ?? ""
            if draftsByKey[meterName] == nil {
                draftsByKey[meterName] = CSVNewMeterDraft(
                    key: meterName,
                    name: meterName,
                    unit: unit
                )
            } else if draftsByKey[meterName]?.unit.isEmpty == true, !unit.isEmpty {
                draftsByKey[meterName]?.unit = unit
            }
        }

        return draftsByKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func result(from previewRows: [CSVImportPreviewRow]) -> CSVImportResult {
        let readings = previewRows.compactMap(\.plannedReading)
        let newMeterKeys = Set(readings.compactMap { reading -> String? in
            if case .new(let key) = reading.meterReference { return key }
            return nil
        })

        return CSVImportResult(
            createdMeters: newMeterKeys.count,
            importedReadings: readings.count,
            skippedDuplicates: previewRows.filter { $0.status == .duplicate }.count,
            skippedInvalidRows: previewRows.filter { $0.status == .invalid || $0.status == .skipped }.count
        )
    }

    static func newMeterDrafts(from mapping: CSVColumnMapping, previewRows: [CSVImportPreviewRow]) -> [CSVNewMeterDraft] {
        let validNewKeys = Set(previewRows.compactMap { row -> String? in
            guard let plannedReading = row.plannedReading, case .new(let key) = plannedReading.meterReference else {
                return nil
            }
            return key
        })

        switch mapping.shape {
        case .wide:
            var seenKeys: Set<String> = []
            return mapping.wideValueMappings.compactMap { valueMapping in
                guard case .new(let draft) = valueMapping.target, validNewKeys.contains(draft.key) else {
                    return nil
                }
                guard seenKeys.insert(draft.key).inserted else { return nil }
                return draft
            }
        case .long:
            return previewRows.compactMap(\.plannedReading?.newMeterDraft)
                .filter { validNewKeys.contains($0.key) }
                .reduce(into: [String: CSVNewMeterDraft]()) { draftsByKey, draft in
                    if draftsByKey[draft.key] == nil {
                        draftsByKey[draft.key] = draft
                    }
                }
                .values
                .sorted { $0.name < $1.name }
        }
    }

    private static func previewWideRow(
        _ row: [String],
        rowNumber: Int,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot],
        seenReadings: inout [CSVPlannedReading],
        calendar: Calendar
    ) -> [CSVImportPreviewRow] {
        let dateText = value(in: row, at: mapping.dateColumnIndex)
        let note = mapping.noteColumnIndex.map { value(in: row, at: $0) } ?? ""

        return mapping.wideValueMappings.map { valueMapping in
            let valueText = value(in: row, at: valueMapping.columnIndex)
            return previewEntry(
                rowNumber: rowNumber,
                meterName: meterName(for: valueMapping.target, existingMeters: existingMeters),
                valueText: valueText,
                dateText: dateText,
                note: note,
                target: valueMapping.target,
                existingMeters: existingMeters,
                seenReadings: &seenReadings,
                calendar: calendar
            )
        }
    }

    private static func previewLongRow(
        _ row: [String],
        rowNumber: Int,
        mapping: CSVColumnMapping,
        existingMeters: [CSVImportMeterSnapshot],
        seenReadings: inout [CSVPlannedReading],
        calendar: Calendar
    ) -> CSVImportPreviewRow {
        guard let meterColumnIndex = mapping.meterColumnIndex, let valueColumnIndex = mapping.valueColumnIndex else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: "", valueText: "", dateText: "", status: .invalid, message: .missingMapping, plannedReading: nil)
        }

        let meterName = CSVSpreadsheetSafety.restoredText(value(in: row, at: meterColumnIndex).trimmingCharacters(in: .whitespacesAndNewlines))
        let valueText = value(in: row, at: valueColumnIndex)
        let dateText = value(in: row, at: mapping.dateColumnIndex)
        let note = mapping.noteColumnIndex.map { CSVSpreadsheetSafety.restoredText(value(in: row, at: $0)) } ?? ""
        let existingMeter = existingMeters.first { $0.name.caseInsensitiveCompare(meterName) == .orderedSame }

        let target: CSVImportMeterTarget
        if let existingMeter {
            target = .existing(existingMeter.id)
        } else if mapping.longCreateMissingMeters {
            let fallbackUnit = mapping.unitColumnIndex.map { CSVSpreadsheetSafety.restoredText(value(in: row, at: $0)) } ?? ""
            let draft = mapping.longNewMeterDrafts[meterName] ?? CSVNewMeterDraft(key: meterName, name: meterName, unit: fallbackUnit)
            target = .new(draft)
        } else {
            target = .ignore
        }

        return previewEntry(
            rowNumber: rowNumber,
            meterName: meterName,
            valueText: valueText,
            dateText: dateText,
            note: note,
            target: target,
            existingMeters: existingMeters,
            seenReadings: &seenReadings,
            calendar: calendar
        )
    }

    private static func previewEntry(
        rowNumber: Int,
        meterName: String,
        valueText: String,
        dateText: String,
        note: String,
        target: CSVImportMeterTarget,
        existingMeters: [CSVImportMeterSnapshot],
        seenReadings: inout [CSVPlannedReading],
        calendar: Calendar
    ) -> CSVImportPreviewRow {
        guard !valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .skipped, message: .emptyValue, plannedReading: nil)
        }

        guard let parsedDate = CSVDateParser.parse(dateText, calendar: calendar) else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .invalid, message: .invalidDate, plannedReading: nil)
        }

        guard let value = CSVNumberParser.parse(valueText), value >= 0 else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .invalid, message: .invalidValue, plannedReading: nil)
        }

        let meterReference: CSVImportMeterReference
        let newMeterDraft: CSVNewMeterDraft?
        switch target {
        case .ignore:
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .skipped, message: .ignored, plannedReading: nil)
        case .existing(let meterID):
            meterReference = .existing(meterID)
            newMeterDraft = nil
        case .new(let draft):
            guard draft.canCreate else {
                return CSVImportPreviewRow(rowNumber: rowNumber, meterName: draft.name, valueText: valueText, dateText: dateText, status: .invalid, message: .missingMeterSetup, plannedReading: nil)
            }
            meterReference = .new(draft.key)
            newMeterDraft = draft
        }

        if isDuplicate(
            meterReference: meterReference,
            date: parsedDate.date,
            granularity: parsedDate.granularity,
            existingMeters: existingMeters,
            seenReadings: seenReadings,
            calendar: calendar
        ) {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .duplicate, message: .duplicate, plannedReading: nil)
        }

        let plannedReading = CSVPlannedReading(
            rowNumber: rowNumber,
            meterReference: meterReference,
            newMeterDraft: newMeterDraft,
            value: value,
            recordedAt: parsedDate.date,
            granularity: parsedDate.granularity,
            note: note
        )
        seenReadings.append(plannedReading)

        return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .valid, message: .ready, plannedReading: plannedReading)
    }

    private static func isDuplicate(
        meterReference: CSVImportMeterReference,
        date: Date,
        granularity: ReadingTimestampGranularity,
        existingMeters: [CSVImportMeterSnapshot],
        seenReadings: [CSVPlannedReading],
        calendar: Calendar
    ) -> Bool {
        if seenReadings.contains(where: {
            $0.meterReference == meterReference
                && MeterAnalytics.readingsConflict($0.recordedAt, $0.granularity, date, granularity, calendar: calendar)
        }) {
            return true
        }

        guard case .existing(let meterID) = meterReference,
              let meter = existingMeters.first(where: { $0.id == meterID }) else {
            return false
        }

        return meter.readings.contains {
            MeterAnalytics.readingsConflict($0.recordedAt, $0.granularity, date, granularity, calendar: calendar)
        }
    }

    private static func meterName(for target: CSVImportMeterTarget, existingMeters: [CSVImportMeterSnapshot]) -> String {
        switch target {
        case .ignore:
            ""
        case .existing(let meterID):
            existingMeters.first(where: { $0.id == meterID })?.name ?? ""
        case .new(let draft):
            draft.name
        }
    }

    private static func value(in row: [String], at index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bestHeaderIndex(in headers: [String], names: [String]) -> Int? {
        let normalizedNames = names.map(normalizedHeader)
        if let exactIndex = headers.firstIndex(where: { header in
            normalizedNames.contains(normalizedHeader(header))
        }) {
            return exactIndex
        }

        return headers.firstIndex { header in
            let headerWords = Set(normalizedHeader(header).split(separator: " ").map(String.init))
            return normalizedNames.contains { name in
                let nameWords = name.split(separator: " ").map(String.init)
                return !nameWords.isEmpty && nameWords.allSatisfy { headerWords.contains($0) }
            }
        }
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isLongMapping(dateIndex: Int, meterIndex: Int?, valueIndex: Int?) -> Bool {
        guard let meterIndex, let valueIndex else { return false }
        return meterIndex != valueIndex
            && meterIndex != dateIndex
            && valueIndex != dateIndex
    }
}
