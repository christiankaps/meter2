import SwiftUI

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
            billingPeriodLabel: ""
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
            billingPeriodLabel: period?.label ?? ""
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
    let onSave: (MeterDraft) -> Bool

    @State private var draft: MeterDraft

    init(mode: MeterFormMode, onSave: @escaping (MeterDraft) -> Bool) {
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: mode.initialDraft)
    }

    var body: some View {
        Form {
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
                TextField(String(localized: "meter.unit"), text: $draft.unit)
                Stepper(
                    String(localized: "meter.decimalPrecision \(draft.decimalPrecision)"),
                    value: $draft.decimalPrecision,
                    in: 0...6
                )
                Toggle(String(localized: "meter.archived"), isOn: $draft.isArchived)
            }

            Section(String(localized: "meter.section.tariff")) {
                TextField(String(localized: "meter.currency"), text: $draft.currencyCode)
                TextField(String(localized: "meter.unitPrice"), value: $draft.unitPrice, format: .number)
                TextField(String(localized: "meter.baseFee"), value: $draft.baseFee, format: .number)
            }

            Section(String(localized: "meter.section.billing")) {
                Toggle(String(localized: "billing.useCustom"), isOn: $draft.usesBillingPeriod)
                if draft.usesBillingPeriod {
                    TextField(String(localized: "billing.label"), text: $draft.billingPeriodLabel)
                    DatePicker(String(localized: "billing.start"), selection: $draft.billingPeriodStart, displayedComponents: .date)
                    DatePicker(String(localized: "billing.end"), selection: $draft.billingPeriodEnd, displayedComponents: .date)
                }
            }

            Section(String(localized: "meter.section.notes")) {
                TextField(String(localized: "note"), text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
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
                .disabled(!draft.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
