import SwiftUI

struct CompanionReadingDraft {
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String
}

struct CompanionReadingFormView: View {
    @Environment(\.dismiss) private var dismiss
    let meter: Meter
    let reading: MeterReading?
    let onSave: (CompanionReadingDraft) -> Bool

    @State private var valueText: String
    @State private var draft: CompanionReadingDraft
    @FocusState private var valueFieldIsFocused: Bool

    init(meter: Meter, reading: MeterReading?, onSave: @escaping (CompanionReadingDraft) -> Bool) {
        self.meter = meter
        self.reading = reading
        self.onSave = onSave
        let initialDraft = CompanionReadingDraft(
            value: reading?.value ?? 0,
            recordedAt: reading?.recordedAt ?? Date(),
            granularity: reading?.recordedAtGranularity ?? .dateTime,
            note: reading?.note ?? ""
        )
        _draft = State(initialValue: initialDraft)
        _valueText = State(initialValue: reading.map { CompanionReadingValueParser.formatForEditing($0.value) } ?? "")
    }

    private var parsedValue: Double? {
        CompanionReadingValueParser.parse(valueText)
    }

    private var validation: ReadingValidationResult {
        guard let parsedValue else {
            return ReadingValidationResult(issues: [])
        }

        return MeterAnalytics.validateReading(
            value: parsedValue,
            recordedAt: MeterAnalytics.normalizedForStorage(draft.recordedAt, granularity: draft.granularity),
            granularity: draft.granularity,
            existingReadings: meter.readings,
            editingReadingID: reading?.id
        )
    }

    private var visibleIssues: [ReadingValidationIssue] {
        valueFieldIsFocused ? validation.blockingIssues : validation.issues
    }

    private var canSave: Bool {
        parsedValue != nil && validation.canSave
    }

    var body: some View {
        Form {
            Section(String(localized: "reading.section.value")) {
                TextField(String(localized: "reading.value"), text: $valueText)
                    .keyboardType(.decimalPad)
                    .focused($valueFieldIsFocused)
                Picker(String(localized: "reading.granularity"), selection: $draft.granularity) {
                    ForEach(ReadingTimestampGranularity.allCases) { granularity in
                        Text(granularity.localizedName)
                            .tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                DatePicker(
                    String(localized: "reading.recordedAt"),
                    selection: $draft.recordedAt,
                    displayedComponents: draft.granularity == .dateOnly ? [.date] : [.date, .hourAndMinute]
                )
                TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
            }

            if !visibleIssues.isEmpty {
                Section(String(localized: "validation.title")) {
                    ForEach(visibleIssues, id: \.rawValue) { issue in
                        Label(issue.localizedMessage, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                }
            }
        }
        .navigationTitle(reading == nil ? String(localized: "reading.add") : String(localized: "reading.edit"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "save")) {
                    guard let parsedValue else { return }
                    draft.value = parsedValue
                    if onSave(draft) {
                        dismiss()
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}

enum CompanionReadingValueParser {
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let localized = NumberFormatter.localizedDecimal.number(from: trimmed)?.doubleValue {
            return localized.isFinite ? localized : nil
        }

        let fallback = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(fallback), value.isFinite else { return nil }
        return value
    }

    static func formatForEditing(_ value: Double) -> String {
        NumberFormatter.editingDecimal.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension NumberFormatter {
    static var localizedDecimal: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter
    }

    static var editingDecimal: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 12
        formatter.minimumFractionDigits = 0
        return formatter
    }
}
