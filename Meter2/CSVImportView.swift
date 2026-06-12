import SwiftUI

struct CSVImportSession: Identifiable {
    let id = UUID()
    var document: CSVDocument
}

struct CSVProgressState: Identifiable {
    let id = UUID()
    var message: String
}

struct CSVImportExecutionPlan {
    var plannedReadings: [CSVPlannedReading]
    var newMeterDrafts: [CSVNewMeterDraft]
    var result: CSVImportResult
}

enum CSVFileAccessError: Error {
    case accessDenied
}

struct CSVImportView: View {
    let document: CSVDocument
    let meters: [Meter]
    let onCancel: () -> Void
    let onImport: (CSVColumnMapping, [CSVImportPreviewRow]) -> Void

    @State private var shape: CSVImportShape
    @State private var dateColumnIndex: Int
    @State private var noteColumnIndex: Int
    @State private var meterColumnIndex: Int
    @State private var valueColumnIndex: Int
    @State private var unitColumnIndex: Int
    @State private var wideTargets: [Int: String]
    @State private var wideDrafts: [Int: CSVNewMeterDraft]
    @State private var longCreateMissingMeters: Bool
    @State private var longDrafts: [String: CSVNewMeterDraft]

    init(
        document: CSVDocument,
        meters: [Meter],
        onCancel: @escaping () -> Void,
        onImport: @escaping (CSVColumnMapping, [CSVImportPreviewRow]) -> Void
    ) {
        let suggestedMapping = CSVImportPlanner.suggestedMapping(for: document, existingMeters: meters)
        self.document = document
        self.meters = meters
        self.onCancel = onCancel
        self.onImport = onImport

        _shape = State(initialValue: suggestedMapping.shape)
        _dateColumnIndex = State(initialValue: suggestedMapping.dateColumnIndex)
        _noteColumnIndex = State(initialValue: suggestedMapping.noteColumnIndex ?? -1)
        _meterColumnIndex = State(initialValue: suggestedMapping.meterColumnIndex ?? 0)
        _valueColumnIndex = State(initialValue: suggestedMapping.valueColumnIndex ?? min(1, max(document.headers.count - 1, 0)))
        _unitColumnIndex = State(initialValue: suggestedMapping.unitColumnIndex ?? -1)
        _wideTargets = State(initialValue: Dictionary(uniqueKeysWithValues: suggestedMapping.wideValueMappings.map { mapping in
            (mapping.columnIndex, CSVImportView.targetSelectionValue(mapping.target))
        }))
        _wideDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: suggestedMapping.wideValueMappings.compactMap { mapping in
            guard case .new(let draft) = mapping.target else { return nil }
            return (mapping.columnIndex, draft)
        }))
        _longCreateMissingMeters = State(initialValue: true)
        _longDrafts = State(initialValue: [:])
    }

    private var mapping: CSVColumnMapping {
        CSVColumnMapping(
            shape: shape,
            dateColumnIndex: dateColumnIndex,
            noteColumnIndex: noteColumnIndex >= 0 ? noteColumnIndex : nil,
            meterColumnIndex: shape == .long ? meterColumnIndex : nil,
            valueColumnIndex: shape == .long ? valueColumnIndex : nil,
            unitColumnIndex: shape == .long && unitColumnIndex >= 0 ? unitColumnIndex : nil,
            wideValueMappings: wideValueMappings,
            longCreateMissingMeters: longCreateMissingMeters,
            longNewMeterDrafts: resolvedLongDrafts
        )
    }

    private var previewRows: [CSVImportPreviewRow] {
        CSVImportPlanner.preview(document: document, mapping: mapping, existingMeters: meters)
    }

    private var result: CSVImportResult {
        CSVImportPlanner.result(from: previewRows)
    }

    private var canImport: Bool {
        result.importedReadings > 0
    }

    private var wideValueMappings: [CSVWideValueMapping] {
        document.headers.indices
            .filter { $0 != dateColumnIndex && $0 != noteColumnIndex && (shape != .long || $0 != unitColumnIndex) }
            .map { index in
                CSVWideValueMapping(columnIndex: index, target: wideTarget(for: index))
            }
    }

    private var missingLongMeterNames: [String] {
        guard shape == .long, document.headers.indices.contains(meterColumnIndex) else { return [] }
        let existingNames = Set(meters.map { $0.name.lowercased() })
        let names = document.rows
            .map { row in
                let meterName = row.indices.contains(meterColumnIndex) ? row[meterColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                return CSVSpreadsheetSafety.restoredText(meterName)
            }
            .filter { !$0.isEmpty && !existingNames.contains($0.lowercased()) }
        return Array(Set(names)).sorted()
    }

    private var resolvedLongDrafts: [String: CSVNewMeterDraft] {
        Dictionary(uniqueKeysWithValues: missingLongMeterNames.map { name in
            (name, longDrafts[name] ?? CSVNewMeterDraft(key: name, name: name, unit: unitForLongMeter(named: name)))
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(String(localized: "csv.import"), systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold))

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CSVImportPanel(title: String(localized: "csv.section.mapping")) {
                            Picker(String(localized: "csv.shape"), selection: $shape) {
                                Text(String(localized: "csv.shape.wide")).tag(CSVImportShape.wide)
                                Text(String(localized: "csv.shape.long")).tag(CSVImportShape.long)
                            }
                            .pickerStyle(.segmented)

                            CSVColumnPicker(title: String(localized: "csv.column.date"), headers: document.headers, selection: $dateColumnIndex, allowsNone: false)
                            CSVColumnPicker(title: String(localized: "csv.column.note"), headers: document.headers, selection: $noteColumnIndex, allowsNone: true)

                            if shape == .long {
                                CSVColumnPicker(title: String(localized: "csv.column.meter"), headers: document.headers, selection: $meterColumnIndex, allowsNone: false)
                                CSVColumnPicker(title: String(localized: "csv.column.value"), headers: document.headers, selection: $valueColumnIndex, allowsNone: false)
                                CSVColumnPicker(title: String(localized: "csv.column.unit"), headers: document.headers, selection: $unitColumnIndex, allowsNone: true)
                                Toggle(String(localized: "csv.createMissingMeters"), isOn: $longCreateMissingMeters)
                            }
                        }

                        if shape == .wide {
                            CSVImportPanel(title: String(localized: "csv.section.meters")) {
                                let valueMappings = wideValueMappings
                                let lastValueMappingID = valueMappings.last?.id

                                ForEach(valueMappings) { valueMapping in
                                    CSVWideMappingRow(
                                        header: document.headers[valueMapping.columnIndex],
                                        meters: meters,
                                        selection: Binding(
                                            get: { wideTargets[valueMapping.columnIndex] ?? "new" },
                                            set: { wideTargets[valueMapping.columnIndex] = $0 }
                                        ),
                                        draft: Binding(
                                            get: { wideDrafts[valueMapping.columnIndex] ?? CSVNewMeterDraft(key: document.headers[valueMapping.columnIndex], name: document.headers[valueMapping.columnIndex], unit: "") },
                                            set: { wideDrafts[valueMapping.columnIndex] = $0 }
                                        )
                                    )

                                    if valueMapping.id != lastValueMappingID {
                                        Divider()
                                    }
                                }
                            }
                        }

                        if shape == .long && longCreateMissingMeters && !missingLongMeterNames.isEmpty {
                            CSVImportPanel(title: String(localized: "csv.section.newMeters")) {
                                ForEach(missingLongMeterNames, id: \.self) { name in
                                    CSVNewMeterFields(
                                        title: name,
                                        draft: Binding(
                                            get: { longDrafts[name] ?? CSVNewMeterDraft(key: name, name: name, unit: unitForLongMeter(named: name)) },
                                            set: { longDrafts[name] = $0 }
                                        )
                                    )

                                    if name != missingLongMeterNames.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 400)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(localized: "csv.section.preview"))
                            .font(.headline)
                        Spacer()
                        Text(String(localized: "csv.previewSummary \(result.importedReadings) \(result.createdMeters) \(result.skippedDuplicates) \(result.skippedInvalidRows)"))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    CSVPreviewList(rows: previewRows)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button(String(localized: "cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "csv.importConfirm")) {
                    onImport(mapping, previewRows)
                }
                .disabled(!canImport)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 1120)
        .frame(minHeight: 620, maxHeight: 760)
        .interactiveDismissDisabled(false)
        .onExitCommand {
            onCancel()
        }
    }

    private func wideTarget(for columnIndex: Int) -> CSVImportMeterTarget {
        let selection = wideTargets[columnIndex] ?? "new"
        if selection == "ignore" { return .ignore }
        if selection == "new" {
            return .new(wideDrafts[columnIndex] ?? CSVNewMeterDraft(key: document.headers[columnIndex], name: document.headers[columnIndex], unit: ""))
        }
        if let id = UUID(uuidString: selection.replacingOccurrences(of: "existing:", with: "")) {
            return .existing(id)
        }
        return .ignore
    }

    private func unitForLongMeter(named meterName: String) -> String {
        guard unitColumnIndex >= 0 else { return "" }

        return document.rows.first { row in
            let rawMeterName = row.indices.contains(meterColumnIndex) ? row[meterColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let rowMeterName = CSVSpreadsheetSafety.restoredText(rawMeterName)
            let rawUnit = row.indices.contains(unitColumnIndex) ? row[unitColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let unit = CSVSpreadsheetSafety.restoredText(rawUnit)
            return rowMeterName == meterName && !unit.isEmpty
        }.map { row in
            let unit = row.indices.contains(unitColumnIndex) ? row[unitColumnIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return CSVSpreadsheetSafety.restoredText(unit)
        } ?? ""
    }

    private static func targetSelectionValue(_ target: CSVImportMeterTarget) -> String {
        switch target {
        case .ignore:
            "ignore"
        case .existing(let id):
            "existing:\(id.uuidString)"
        case .new:
            "new"
        }
    }
}

struct CSVImportPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CSVColumnPicker: View {
    let title: String
    let headers: [String]
    @Binding var selection: Int
    let allowsNone: Bool

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone {
                Text(String(localized: "csv.column.none")).tag(-1)
            }
            ForEach(headers.indices, id: \.self) { index in
                Text(headers[index]).tag(index)
            }
        }
    }
}

struct CSVWideMappingRow: View {
    let header: String
    let meters: [Meter]
    @Binding var selection: String
    @Binding var draft: CSVNewMeterDraft

    var body: some View {
        VStack(alignment: .leading) {
            Text(header)
                .font(.headline)
            Picker(String(localized: "csv.mapping.target"), selection: $selection) {
                Text(String(localized: "csv.mapping.ignore")).tag("ignore")
                Text(String(localized: "csv.mapping.create")).tag("new")
                ForEach(meters) { meter in
                    Text(meter.name).tag("existing:\(meter.id.uuidString)")
                }
            }
            if selection == "new" {
                CSVNewMeterFields(title: String(localized: "csv.mapping.create"), draft: $draft)
            }
        }
    }
}

struct CSVNewMeterFields: View {
    let title: String
    @Binding var draft: CSVNewMeterDraft

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "meter.name"), text: $draft.name)
            }
            GridRow {
                Text(String(localized: "meter.unit"))
                    .foregroundStyle(.secondary)
                TextField(String(localized: "meter.unit"), text: $draft.unit)
            }
            GridRow {
                Text(String(localized: "meter.location"))
                    .foregroundStyle(.secondary)
                TextField(String(localized: "meter.location"), text: $draft.location)
            }
            GridRow {
                Text(String(localized: "meter.decimalPrecision.short"))
                    .foregroundStyle(.secondary)
                Stepper("\(draft.decimalPrecision)", value: $draft.decimalPrecision, in: 0...6)
            }
        }
    }
}

struct CSVPreviewList: View {
    let rows: [CSVImportPreviewRow]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(rows.prefix(80)) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("#\(row.rowNumber)")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(row.meterName.isEmpty ? String(localized: "csv.mapping.ignore") : row.meterName)
                            .lineLimit(1)
                            .frame(width: 190, alignment: .leading)
                        Text(row.dateText)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                        Text(row.valueText)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .trailing)
                        Label(CSVPreviewStatusLabel.text(for: row.status), systemImage: CSVPreviewStatusLabel.systemImage(for: row.status))
                            .foregroundStyle(CSVPreviewStatusLabel.color(for: row.status))
                            .frame(width: 130, alignment: .leading)
                        if row.status != .valid {
                            Text(row.message.localizedText)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 220, alignment: .leading)
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 900, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

enum CSVPreviewStatusLabel {
    static func text(for status: CSVImportPreviewStatus) -> String {
        switch status {
        case .valid:
            String(localized: "csv.status.valid")
        case .duplicate:
            String(localized: "csv.status.duplicate")
        case .skipped:
            String(localized: "csv.status.skipped")
        case .invalid:
            String(localized: "csv.status.invalid")
        }
    }

    static func systemImage(for status: CSVImportPreviewStatus) -> String {
        switch status {
        case .valid:
            "checkmark.circle.fill"
        case .duplicate:
            "arrow.triangle.2.circlepath.circle.fill"
        case .skipped:
            "minus.circle.fill"
        case .invalid:
            "xmark.octagon.fill"
        }
    }

    static func color(for status: CSVImportPreviewStatus) -> Color {
        switch status {
        case .valid:
            .green
        case .duplicate:
            .blue
        case .skipped:
            .orange
        case .invalid:
            .red
        }
    }
}
