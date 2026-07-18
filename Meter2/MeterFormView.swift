import SwiftUI

struct VirtualMeterTermDraft: Identifiable {
    var id: UUID = UUID()
    var sourceID: UUID?
    var operation: VirtualMeterOperation = .add
}

struct MeterDraft {
    var name: String
    var kind: MeterKind
    var location: String
    var unit: String
    var decimalPrecision: Int
    var isArchived: Bool
    var note: String
    var currencyCode: String
    var unitPrice: Double
    var baseFee: Double
    var usesBillingPeriod: Bool
    var billingPeriodStart: Date
    var billingPeriodEnd: Date
    var billingPeriodLabel: String
    var dataSourceKind: MeterDataSourceKind
    var virtualTerms: [VirtualMeterTermDraft]

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && decimalPrecision >= 0
            && (!usesBillingPeriod || billingPeriodEnd > billingPeriodStart)
    }

    static func empty() -> MeterDraft {
        let period = MeterAnalytics.defaultBillingPeriod(containing: Date())
        return MeterDraft(
            name: "",
            kind: .electricity,
            location: "",
            unit: MeterKind.electricity.defaultUnit,
            decimalPrecision: 1,
            isArchived: false,
            note: "",
            currencyCode: Locale.current.currency?.identifier ?? "EUR",
            unitPrice: 0,
            baseFee: 0,
            usesBillingPeriod: false,
            billingPeriodStart: period.0,
            billingPeriodEnd: period.1,
            billingPeriodLabel: "",
            dataSourceKind: .manual,
            virtualTerms: []
        )
    }

    static func from(_ meter: Meter) -> MeterDraft {
        let period = meter.activeBillingPeriod
        let defaultPeriod = MeterAnalytics.defaultBillingPeriod(containing: Date())
        let tariff = meter.activeTariff

        return MeterDraft(
            name: meter.name,
            kind: meter.kind,
            location: meter.location,
            unit: meter.unit,
            decimalPrecision: meter.decimalPrecision,
            isArchived: meter.isArchived,
            note: meter.note,
            currencyCode: tariff?.currencyCode ?? Locale.current.currency?.identifier ?? "EUR",
            unitPrice: tariff?.unitPrice ?? 0,
            baseFee: tariff?.baseFee ?? 0,
            usesBillingPeriod: period != nil,
            billingPeriodStart: period?.startsAt ?? defaultPeriod.0,
            billingPeriodEnd: period?.endsAt ?? defaultPeriod.1,
            billingPeriodLabel: period?.label ?? "",
            dataSourceKind: meter.dataSourceKind,
            virtualTerms: meter.sortedVirtualTerms.map {
                VirtualMeterTermDraft(id: $0.id, sourceID: $0.source?.id, operation: $0.operation)
            }
        )
    }
}

enum MeterFormMode {
    case add
    case edit(Meter)

    var title: String {
        switch self {
        case .add:
            String(localized: "meter.add")
        case .edit:
            String(localized: "meter.edit")
        }
    }

    var initialDraft: MeterDraft {
        switch self {
        case .add:
            .empty()
        case .edit(let meter):
            .from(meter)
        }
    }
}

struct MeterFormView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: MeterFormMode
    let meters: [Meter]
    let onSave: (MeterDraft) -> Bool

    @State private var draft: MeterDraft
    @State private var isTariffExpanded: Bool
    @State private var isBillingExpanded: Bool
    @State private var isNotesExpanded: Bool

    init(mode: MeterFormMode, meters: [Meter], onSave: @escaping (MeterDraft) -> Bool) {
        self.mode = mode
        self.meters = meters
        self.onSave = onSave
        _draft = State(initialValue: mode.initialDraft)
        _isTariffExpanded = State(initialValue: mode.initialDraft.unitPrice != 0 || mode.initialDraft.baseFee != 0)
        _isBillingExpanded = State(initialValue: mode.initialDraft.usesBillingPeriod)
        _isNotesExpanded = State(initialValue: !mode.initialDraft.note.isEmpty)
    }

    private var selectableSources: [Meter] {
        meters.filter { !$0.isVirtual && $0.id != editedMeterID }
    }

    private var editedMeterID: UUID? {
        guard case .edit(let meter) = mode else { return nil }
        return meter.id
    }

    private var selectedSources: [Meter] {
        draft.virtualTerms.compactMap { term in
            selectableSources.first { $0.id == term.sourceID }
        }
    }

    private var hasValidFormula: Bool {
        let sourceIDs = draft.virtualTerms.compactMap(\.sourceID)
        guard !draft.virtualTerms.isEmpty,
              sourceIDs.count == draft.virtualTerms.count,
              Set(sourceIDs).count == sourceIDs.count,
              selectedSources.count == sourceIDs.count,
              let unit = selectedSources.first?.unit else {
            return false
        }
        return selectedSources.allSatisfy { $0.unit == unit }
    }

    private var canSave: Bool {
        draft.canSave && (draft.dataSourceKind == .manual || hasValidFormula)
    }

    var body: some View {
        Form {
            Section(String(localized: "meter.section.source")) {
                Picker(String(localized: "meter.source.type"), selection: $draft.dataSourceKind) {
                    ForEach(MeterDataSourceKind.allCases) { sourceKind in
                        Text(sourceKind.localizedName).tag(sourceKind)
                    }
                }
                .disabled(editedMeterID != nil)

                if draft.dataSourceKind == .virtual {
                    virtualFormulaFields
                }
            }

            Section(String(localized: "meter.section.general")) {
                TextField(String(localized: "meter.name"), text: $draft.name)
                Picker(String(localized: "meter.kind"), selection: $draft.kind) {
                    ForEach(MeterKind.allCases) { kind in
                        Label(kind.localizedName, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
                .onChange(of: draft.kind) { _, newKind in
                    if draft.unit.isEmpty {
                        draft.unit = newKind.defaultUnit
                    }
                }
                TextField(String(localized: "meter.location"), text: $draft.location)
                if draft.dataSourceKind == .manual {
                    TextField(String(localized: "meter.unit"), text: $draft.unit)
                } else {
                    LabeledContent(String(localized: "meter.unit"), value: selectedSources.first?.unit ?? String(localized: "notAvailable"))
                }
                Stepper(
                    String(localized: "meter.decimalPrecision \(draft.decimalPrecision)"),
                    value: $draft.decimalPrecision,
                    in: 0...6
                )
                Toggle(String(localized: "meter.archived"), isOn: $draft.isArchived)
            }

            Section {
                DisclosureGroup(String(localized: "meter.section.tariff"), isExpanded: $isTariffExpanded) {
                    TextField(String(localized: "meter.currency"), text: $draft.currencyCode)
                    TextField(String(localized: "meter.unitPrice"), value: $draft.unitPrice, format: .number)
                    TextField(String(localized: "meter.baseFee"), value: $draft.baseFee, format: .number)
                }
            }

            Section {
                DisclosureGroup(String(localized: "meter.section.billing"), isExpanded: $isBillingExpanded) {
                    Toggle(String(localized: "billing.useCustom"), isOn: $draft.usesBillingPeriod)
                    if draft.usesBillingPeriod {
                        TextField(String(localized: "billing.label"), text: $draft.billingPeriodLabel)
                        DatePicker(String(localized: "billing.start"), selection: $draft.billingPeriodStart, displayedComponents: .date)
                        DatePicker(String(localized: "billing.end"), selection: $draft.billingPeriodEnd, displayedComponents: .date)
                    }
                }
            }

            Section {
                DisclosureGroup(String(localized: "meter.section.notes"), isExpanded: $isNotesExpanded) {
                    TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
        }
        .padding()
        .frame(width: 460)
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
                    if onSave(draft) {
                        dismiss()
                    }
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var virtualFormulaFields: some View {
        ForEach($draft.virtualTerms) { $term in
            HStack {
                Picker(String(localized: "virtualMeter.operation"), selection: $term.operation) {
                    ForEach(VirtualMeterOperation.allCases) { operation in
                        Text(operation.symbol).tag(operation)
                    }
                }
                .labelsHidden()
                .frame(width: 54)

                Picker(String(localized: "virtualMeter.source"), selection: $term.sourceID) {
                    Text(String(localized: "virtualMeter.source.choose")).tag(nil as UUID?)
                    ForEach(selectableSources) { meter in
                        Text("\(meter.name) (\(meter.unit))").tag(meter.id as UUID?)
                    }
                }

                Button(role: .destructive) {
                    draft.virtualTerms.removeAll { $0.id == term.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "virtualMeter.term.remove"))
            }
        }

        Button {
            draft.virtualTerms.append(
                VirtualMeterTermDraft(operation: draft.virtualTerms.isEmpty ? .add : .subtract)
            )
        } label: {
            Label(String(localized: "virtualMeter.term.add"), systemImage: "plus")
        }

        if !draft.virtualTerms.isEmpty, !hasValidFormula {
            Text(String(localized: "virtualMeter.validation.formula"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
