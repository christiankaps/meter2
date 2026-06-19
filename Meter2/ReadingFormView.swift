import AppKit
import SwiftUI

struct ReadingDraft {
    var value: Double
    var recordedAt: Date
    var granularity: ReadingTimestampGranularity
    var note: String

    static func empty() -> ReadingDraft {
        ReadingDraft(value: 0, recordedAt: Calendar.current.startOfDay(for: Date()), granularity: .dateOnly, note: "")
    }

    static func from(_ reading: MeterReading) -> ReadingDraft {
        ReadingDraft(value: reading.value, recordedAt: reading.recordedAt, granularity: reading.recordedAtGranularity, note: reading.note)
    }
}

enum ReadingValueParser {
    static func formatForEditing(_ value: Double, locale: Locale = .current) -> String {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let roundTrippingText = String(value)
        guard decimalSeparator != "." else { return roundTrippingText }

        return roundTrippingText.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false

        if let number = formatter.number(from: trimmedText) {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }

        let normalizedText = trimmedText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalizedText), value.isFinite else {
            return nil
        }

        return value
    }
}

struct ReadingDateInput: Equatable {
    var date: Date
    var granularity: ReadingTimestampGranularity
}

enum ReadingDateInputParser {
    static func parse(_ text: String, calendar: Calendar = .current, locale: Locale = .current) -> ReadingDateInput? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard !value.contains("-") else { return nil }

        for format in localizedDateTimeFormats(locale: locale, calendar: calendar) + dateTimeFormats {
            if let date = formatter(format: format, calendar: calendar, locale: locale).date(from: value) {
                return ReadingDateInput(
                    date: MeterAnalytics.normalizedToDisplayedMinute(date, calendar: calendar),
                    granularity: .dateTime
                )
            }
        }

        for format in localizedDateOnlyFormats(locale: locale, calendar: calendar) + dateOnlyFormats {
            if let date = formatter(format: format, calendar: calendar, locale: locale).date(from: value) {
                return ReadingDateInput(date: calendar.startOfDay(for: date), granularity: .dateOnly)
            }
        }

        return nil
    }

    static func format(_ input: ReadingDateInput, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch input.granularity {
        case .dateOnly:
            return localizedFormatter(template: "yMd", calendar: calendar, locale: locale).string(from: input.date)
        case .dateTime:
            return localizedFormatter(template: "yMdHm", calendar: calendar, locale: locale).string(from: input.date)
        }
    }

    static func format(date: Date, granularity: ReadingTimestampGranularity, calendar: Calendar = .current, locale: Locale = .current) -> String {
        format(ReadingDateInput(date: date, granularity: granularity), calendar: calendar, locale: locale)
    }

    static func addingDays(_ days: Int, to text: String, fallback: ReadingDateInput, calendar: Calendar = .current, locale: Locale = .current) -> ReadingDateInput {
        let input = parse(text, calendar: calendar, locale: locale) ?? fallback
        let steppedDate = calendar.date(byAdding: .day, value: days, to: input.date) ?? input.date
        let normalizedDate: Date
        switch input.granularity {
        case .dateOnly:
            normalizedDate = calendar.startOfDay(for: steppedDate)
        case .dateTime:
            normalizedDate = MeterAnalytics.normalizedToDisplayedMinute(steppedDate, calendar: calendar)
        }
        return ReadingDateInput(date: normalizedDate, granularity: input.granularity)
    }

    static func changingGranularity(
        _ input: ReadingDateInput,
        to granularity: ReadingTimestampGranularity,
        calendar: Calendar = .current
    ) -> ReadingDateInput {
        let normalizedDate: Date
        if input.granularity == granularity {
            normalizedDate = input.date
        } else {
            normalizedDate = calendar.startOfDay(for: input.date)
        }
        return ReadingDateInput(date: normalizedDate, granularity: granularity)
    }

    private static let dateOnlyFormats = [
        "ddMMyyyy",
        "yyyyMMdd",
        "dd.MM.yyyy",
        "dd.MM.yy",
        "yyyy/MM/dd"
    ]

    private static let dateTimeFormats = [
        "ddMMyyyy HHmm",
        "ddMMyyyy HH:mm",
        "yyyyMMdd HHmm",
        "yyyyMMdd HH:mm",
        "dd.MM.yyyy HH:mm",
        "dd.MM.yyyy HHmm",
        "dd.MM.yy HH:mm",
        "yyyy/MM/dd HH:mm"
    ]

    private static func formatter(format: String, calendar: Calendar, locale: Locale = Locale(identifier: "en_US_POSIX")) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static func localizedDateOnlyFormats(locale: Locale, calendar: Calendar) -> [String] {
        [localizedFormatter(template: "yMd", calendar: calendar, locale: locale).dateFormat]
            .compactMap { $0 }
    }

    private static func localizedDateTimeFormats(locale: Locale, calendar: Calendar) -> [String] {
        [localizedFormatter(template: "yMdHm", calendar: calendar, locale: locale).dateFormat]
            .compactMap { $0 }
    }

    private static func localizedFormatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatter.isLenient = false
        return formatter
    }
}

struct ReadingDateTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onTextChange: (String) -> Void
    let onStepDays: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DateStepTextField {
        let textField = DateStepTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.onStepDays = onStepDays
        textField.bezelStyle = .roundedBezel
        textField.isBordered = true
        textField.isEditable = true
        textField.isSelectable = true
        return textField
    }

    func updateNSView(_ textField: DateStepTextField, context: Context) {
        context.coordinator.parent = self
        textField.onStepDays = onStepDays
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ReadingDateTextField

        init(parent: ReadingDateTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
            parent.onTextChange(textField.stringValue)
        }
    }
}

final class DateStepTextField: NSTextField {
    var onStepDays: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+":
            onStepDays?(1)
        case "-":
            onStepDays?(-1)
        default:
            super.keyDown(with: event)
        }
    }
}

enum ReadingFormMode {
    case add(Meter)
    case edit(MeterReading)

    var title: String {
        switch self {
        case .add:
            String(localized: "reading.add")
        case .edit:
            String(localized: "reading.edit")
        }
    }

    var meter: Meter? {
        switch self {
        case .add(let meter):
            meter
        case .edit(let reading):
            reading.meter
        }
    }

    var editingReadingID: UUID? {
        switch self {
        case .add:
            nil
        case .edit(let reading):
            reading.id
        }
    }

    var initialDraft: ReadingDraft {
        switch self {
        case .add:
            .empty()
        case .edit(let reading):
            .from(reading)
        }
    }
}

struct ReadingFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: ReadingFormMode
    let onSave: (ReadingDraft) -> Bool

    @State private var draft: ReadingDraft
    @State private var dateText: String
    @State private var valueText: String
    @FocusState private var valueFieldIsFocused: Bool

    init(mode: ReadingFormMode, onSave: @escaping (ReadingDraft) -> Bool) {
        let initialDraft = mode.initialDraft
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _dateText = State(initialValue: ReadingDateInputParser.format(date: initialDraft.recordedAt, granularity: initialDraft.granularity))
        _valueText = State(initialValue: mode.editingReadingID == nil ? "" : ReadingValueParser.formatForEditing(initialDraft.value))
    }

    private var parsedValue: Double? {
        ReadingValueParser.parse(valueText)
    }

    private var parsedDateInput: ReadingDateInput? {
        ReadingDateInputParser.parse(dateText)
    }

    private var validation: ReadingValidationResult {
        guard let parsedValue, let parsedDateInput else {
            return ReadingValidationResult(issues: [])
        }

        return MeterAnalytics.validateReading(
            value: parsedValue,
            recordedAt: MeterAnalytics.normalizedForStorage(parsedDateInput.date, granularity: parsedDateInput.granularity),
            granularity: parsedDateInput.granularity,
            existingReadings: mode.meter?.readings ?? [],
            editingReadingID: mode.editingReadingID
        )
    }

    private var visibleIssues: [ReadingValidationIssue] {
        if valueFieldIsFocused {
            validation.blockingIssues
        } else {
            validation.issues
        }
    }

    private var canSave: Bool {
        parsedValue != nil && parsedDateInput != nil && validation.canSave
    }

    var body: some View {
        Form {
            Section(String(localized: "reading.section.value")) {
                ReadingDateTextField(
                    placeholder: String(localized: "reading.recordedAt"),
                    text: $dateText,
                    onTextChange: updateDraftDate,
                    onStepDays: stepDate
                )
                Picker(
                    String(localized: "reading.granularity"),
                    selection: Binding(
                        get: { draft.granularity },
                        set: { applyGranularity($0) }
                    )
                ) {
                    ForEach(ReadingTimestampGranularity.allCases) { granularity in
                        Text(granularity.localizedName)
                            .tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
                TextField(String(localized: "reading.value"), text: $valueText)
                    .focused($valueFieldIsFocused)
                TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
            }

            if parsedDateInput == nil || !visibleIssues.isEmpty {
                Section(String(localized: "validation.title")) {
                    if parsedDateInput == nil {
                        Label(String(localized: "reading.validation.invalidDate"), systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }

                    ForEach(visibleIssues, id: \.rawValue) { issue in
                        Label(issue.localizedMessage, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.isBlocking ? .red : .orange)
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "save")) {
                    save(dismissAfterSave: true)
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            if mode.editingReadingID == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "reading.saveAndNext")) {
                        save(dismissAfterSave: false)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func updateDraftDate(_ text: String) {
        guard let parsedDateInput = ReadingDateInputParser.parse(text) else { return }
        draft.recordedAt = parsedDateInput.date
        draft.granularity = parsedDateInput.granularity
    }

    private func applyGranularity(_ granularity: ReadingTimestampGranularity) {
        let currentInput = parsedDateInput ?? ReadingDateInput(date: draft.recordedAt, granularity: draft.granularity)
        let adjustedInput = ReadingDateInputParser.changingGranularity(currentInput, to: granularity)
        draft.recordedAt = adjustedInput.date
        draft.granularity = granularity
        dateText = ReadingDateInputParser.format(adjustedInput)
    }

    private func stepDate(by days: Int) {
        let fallback = ReadingDateInput(date: draft.recordedAt, granularity: draft.granularity)
        let steppedDate = ReadingDateInputParser.addingDays(days, to: dateText, fallback: fallback)
        draft.recordedAt = steppedDate.date
        draft.granularity = steppedDate.granularity
        dateText = ReadingDateInputParser.format(steppedDate)
    }

    private func save(dismissAfterSave: Bool) {
        guard let parsedValue, let parsedDateInput else { return }
        var savedDraft = draft
        savedDraft.value = parsedValue
        savedDraft.recordedAt = parsedDateInput.date
        savedDraft.granularity = parsedDateInput.granularity
        guard onSave(savedDraft) else { return }

        if dismissAfterSave {
            dismiss()
        } else {
            valueText = ""
            draft.note = ""
        }
    }
}
