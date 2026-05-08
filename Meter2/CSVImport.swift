import Foundation

struct CSVDocument: Equatable {
    var headers: [String]
    var rows: [[String]]
    var delimiter: Character
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
        "yyyy-MM-dd",
        "dd.MM.yyyy",
        "MM/dd/yyyy",
        "yyyy/MM/dd"
    ]

    private static let dateTimeFormats = [
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

enum CSVImportShape: String, CaseIterable, Identifiable {
    case wide
    case long

    var id: String { rawValue }
}

struct CSVNewMeterDraft: Equatable {
    var key: String
    var name: String
    var unit: String
    var location: String = ""
    var decimalPrecision: Int = 1

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum CSVImportMeterTarget: Equatable {
    case ignore
    case existing(UUID)
    case new(CSVNewMeterDraft)
}

struct CSVWideValueMapping: Equatable, Identifiable {
    var id: Int { columnIndex }
    var columnIndex: Int
    var target: CSVImportMeterTarget
}

struct CSVColumnMapping: Equatable {
    var shape: CSVImportShape
    var dateColumnIndex: Int
    var noteColumnIndex: Int?
    var meterColumnIndex: Int?
    var valueColumnIndex: Int?
    var wideValueMappings: [CSVWideValueMapping] = []
    var longCreateMissingMeters: Bool = true
    var longNewMeterDrafts: [String: CSVNewMeterDraft] = [:]
}

enum CSVImportPreviewStatus: String, Equatable {
    case valid
    case duplicate
    case skipped
    case invalid
}

enum CSVImportPreviewMessage: String, Equatable {
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

enum CSVImportMeterReference: Hashable, Equatable {
    case existing(UUID)
    case new(String)
}

struct CSVPlannedReading: Equatable {
    var rowNumber: Int
    var meterReference: CSVImportMeterReference
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String
}

struct CSVImportPreviewRow: Identifiable, Equatable {
    var id = UUID()
    var rowNumber: Int
    var meterName: String
    var valueText: String
    var dateText: String
    var status: CSVImportPreviewStatus
    var message: CSVImportPreviewMessage
    var plannedReading: CSVPlannedReading?
}

struct CSVImportResult: Equatable {
    var createdMeters: Int
    var importedReadings: Int
    var skippedDuplicates: Int
    var skippedInvalidRows: Int
}

enum CSVImportPlanner {
    static func suggestedMapping(for document: CSVDocument, existingMeters: [Meter]) -> CSVColumnMapping {
        let dateIndex = bestHeaderIndex(in: document.headers, names: ["date", "datum", "recorded", "recorded at", "timestamp"]) ?? 0
        let noteIndex = bestHeaderIndex(in: document.headers, names: ["note", "notes", "notiz", "bemerkung"])
        let meterIndex = bestHeaderIndex(in: document.headers, names: ["meter", "zähler", "zaehler", "name"])
        let valueIndex = bestHeaderIndex(in: document.headers, names: ["value", "wert", "reading", "zählerstand", "zaehlerstand"])
        let shape: CSVImportShape = meterIndex != nil && valueIndex != nil ? .long : .wide

        var existingByName: [String: UUID] = [:]
        for meter in existingMeters {
            let key = normalizedLookupKey(meter.name)
            if existingByName[key] == nil {
                existingByName[key] = meter.id
            }
        }
        let wideMappings = document.headers.enumerated()
            .filter { index, _ in index != dateIndex && index != noteIndex }
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
            wideValueMappings: wideMappings
        )
    }

    static func preview(
        document: CSVDocument,
        mapping: CSVColumnMapping,
        existingMeters: [Meter],
        calendar: Calendar = .current
    ) -> [CSVImportPreviewRow] {
        var rows: [CSVImportPreviewRow] = []
        var seenReadings: [CSVPlannedReading] = []

        for (rowIndex, row) in document.rows.enumerated() {
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
            return mapping.longNewMeterDrafts.values
                .filter { validNewKeys.contains($0.key) }
                .sorted { $0.name < $1.name }
        }
    }

    private static func previewWideRow(
        _ row: [String],
        rowNumber: Int,
        mapping: CSVColumnMapping,
        existingMeters: [Meter],
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
        existingMeters: [Meter],
        seenReadings: inout [CSVPlannedReading],
        calendar: Calendar
    ) -> CSVImportPreviewRow {
        guard let meterColumnIndex = mapping.meterColumnIndex, let valueColumnIndex = mapping.valueColumnIndex else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: "", valueText: "", dateText: "", status: .invalid, message: .missingMapping, plannedReading: nil)
        }

        let meterName = value(in: row, at: meterColumnIndex).trimmingCharacters(in: .whitespacesAndNewlines)
        let valueText = value(in: row, at: valueColumnIndex)
        let dateText = value(in: row, at: mapping.dateColumnIndex)
        let note = mapping.noteColumnIndex.map { value(in: row, at: $0) } ?? ""
        let existingMeter = existingMeters.first { $0.name.caseInsensitiveCompare(meterName) == .orderedSame }

        let target: CSVImportMeterTarget
        if let existingMeter {
            target = .existing(existingMeter.id)
        } else if mapping.longCreateMissingMeters {
            let draft = mapping.longNewMeterDrafts[meterName] ?? CSVNewMeterDraft(key: meterName, name: meterName, unit: "")
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
        existingMeters: [Meter],
        seenReadings: inout [CSVPlannedReading],
        calendar: Calendar
    ) -> CSVImportPreviewRow {
        guard !valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .skipped, message: .emptyValue, plannedReading: nil)
        }

        guard let parsedDate = CSVDateParser.parse(dateText, calendar: calendar) else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .invalid, message: .invalidDate, plannedReading: nil)
        }

        guard let value = ReadingValueParser.parse(valueText), value >= 0 else {
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .invalid, message: .invalidValue, plannedReading: nil)
        }

        let meterReference: CSVImportMeterReference
        switch target {
        case .ignore:
            return CSVImportPreviewRow(rowNumber: rowNumber, meterName: meterName, valueText: valueText, dateText: dateText, status: .skipped, message: .ignored, plannedReading: nil)
        case .existing(let meterID):
            meterReference = .existing(meterID)
        case .new(let draft):
            guard draft.canCreate else {
                return CSVImportPreviewRow(rowNumber: rowNumber, meterName: draft.name, valueText: valueText, dateText: dateText, status: .invalid, message: .missingMeterSetup, plannedReading: nil)
            }
            meterReference = .new(draft.key)
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
        existingMeters: [Meter],
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
            MeterAnalytics.readingsConflict($0.recordedAt, $0.recordedAtGranularity, date, granularity, calendar: calendar)
        }
    }

    private static func meterName(for target: CSVImportMeterTarget, existingMeters: [Meter]) -> String {
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
        headers.firstIndex { header in
            let normalizedHeader = header.lowercased()
            return names.contains { normalizedHeader == $0 || normalizedHeader.contains($0) }
        }
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
