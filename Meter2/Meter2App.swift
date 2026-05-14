import SwiftUI
import SwiftData

struct Meter2CommandActions {
    var addMeter: (() -> Void)?
    var addReading: (() -> Void)?
    var importCSV: (() -> Void)?
    var exportCSV: (() -> Void)?
    var showHelp: () -> Void
}

private struct Meter2CommandActionsKey: FocusedValueKey {
    typealias Value = Meter2CommandActions
}

extension FocusedValues {
    var meter2CommandActions: Meter2CommandActions? {
        get { self[Meter2CommandActionsKey.self] }
        set { self[Meter2CommandActionsKey.self] = newValue }
    }
}

@main
struct Meter2App: App {
    @StateObject private var syncService = MeterLibrarySyncService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncService)
        }
        .modelContainer(for: [
            Meter.self,
            MeterReading.self,
            MeterTariff.self,
            BillingPeriod.self
        ])
        .defaultSize(
            width: AppConfiguration.defaultWindowWidth,
            height: AppConfiguration.defaultWindowHeight
        )
        .commands {
            Meter2Commands()
        }
    }
}

struct Meter2Commands: Commands {
    @FocusedValue(\.meter2CommandActions) private var commandActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "meter.add")) {
                commandActions?.addMeter?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(commandActions?.addMeter == nil)

            Button(String(localized: "reading.add")) {
                commandActions?.addReading?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(commandActions?.addReading == nil)
        }

        CommandMenu(String(localized: "commands.data")) {
            Button(String(localized: "csv.import")) {
                commandActions?.importCSV?()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(commandActions?.importCSV == nil)

            Button(String(localized: "csv.export")) {
                commandActions?.exportCSV?()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(commandActions?.exportCSV == nil)
        }

        CommandGroup(replacing: .help) {
            Button(String(localized: "help.shortcuts")) {
                commandActions?.showHelp()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            .disabled(commandActions == nil)
        }
    }
}
