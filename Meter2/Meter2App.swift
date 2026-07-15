import AppKit
import SwiftData
import SwiftUI

struct Meter2CommandActions {
    var addMeter: (() -> Void)?
    var addReading: (() -> Void)?
    var editSelectedMeter: (() -> Void)?
    var deleteSelectedMeter: (() -> Void)?
    var importCSV: (() -> Void)?
    var exportContextualCSV: (() -> Void)?
    var exportAllReadingsCSV: (() -> Void)?
    var exportSelectedMeterCSV: (() -> Void)?
    var exportSelectedMeterReport: (() -> Void)?
    var printSelectedMeterReport: (() -> Void)?
    var exportAllActiveMetersReport: (() -> Void)?
    var printAllActiveMetersReport: (() -> Void)?
    var loadExampleData: (() -> Void)?
    var deleteExampleData: (() -> Void)?
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

final class Meter2ApplicationDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("Meter2MainWindow")

    private let terminateApplication: () -> Void
    private let notificationCenter: NotificationCenter

    override init() {
        self.terminateApplication = { NSApp.terminate(nil) }
        self.notificationCenter = .default
        super.init()
    }

    init(
        terminateApplication: @escaping () -> Void,
        notificationCenter: NotificationCenter = .default
    ) {
        self.terminateApplication = terminateApplication
        self.notificationCenter = notificationCenter
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notificationCenter.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    static func shouldTerminateAfterClosingMainWindow(
        _ closingWindow: NSWindow
    ) -> Bool {
        closingWindow.identifier == mainWindowIdentifier
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              Self.shouldTerminateAfterClosingMainWindow(closingWindow) else {
            return
        }

        terminateApplication()
    }
}

final class Meter2MainWindowMarkerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.identifier = Meter2ApplicationDelegate.mainWindowIdentifier
    }
}

private struct Meter2MainWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        Meter2MainWindowMarkerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = Meter2ApplicationDelegate.mainWindowIdentifier
    }
}

@main
struct Meter2App: App {
    @NSApplicationDelegateAdaptor(Meter2ApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Window(String(localized: "app.name"), id: "main") {
            ContentView()
                .background(Meter2MainWindowMarker())
        }
        .modelContainer(for: [
            Meter.self,
            MeterReading.self,
            MeterTariff.self,
            BillingPeriod.self,
            VirtualMeterTerm.self
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
    @ObservedObject private var updateService = AppUpdateService.shared

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "about.menu")) {
                Meter2AboutWindowController.shared.show()
            }
        }

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

        CommandMenu(String(localized: "commands.meter")) {
            Button(String(localized: "meter.edit")) {
                commandActions?.editSelectedMeter?()
            }
            .disabled(commandActions?.editSelectedMeter == nil)

            Button(String(localized: "meter.delete"), role: .destructive) {
                commandActions?.deleteSelectedMeter?()
            }
            .disabled(commandActions?.deleteSelectedMeter == nil)
        }

        CommandMenu(String(localized: "commands.data")) {
            Button(String(localized: "csv.import")) {
                commandActions?.importCSV?()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(commandActions?.importCSV == nil)

            Button(String(localized: "csv.export")) {
                commandActions?.exportContextualCSV?()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(commandActions?.exportContextualCSV == nil)

            Divider()

            Button(String(localized: "csv.export.all")) {
                commandActions?.exportAllReadingsCSV?()
            }
            .disabled(commandActions?.exportAllReadingsCSV == nil)

            Button(String(localized: "csv.export.selectedMeter")) {
                commandActions?.exportSelectedMeterCSV?()
            }
            .disabled(commandActions?.exportSelectedMeterCSV == nil)

            Divider()

            Button(String(localized: "exampleData.load")) {
                commandActions?.loadExampleData?()
            }
            .disabled(commandActions?.loadExampleData == nil)

            Button(String(localized: "exampleData.delete"), role: .destructive) {
                commandActions?.deleteExampleData?()
            }
            .disabled(commandActions?.deleteExampleData == nil)
        }

        CommandMenu(String(localized: "report.menu")) {
            Button(String(localized: "report.export.selected")) {
                commandActions?.exportSelectedMeterReport?()
            }
            .disabled(commandActions?.exportSelectedMeterReport == nil)

            Button(String(localized: "report.print.selected")) {
                commandActions?.printSelectedMeterReport?()
            }
            .disabled(commandActions?.printSelectedMeterReport == nil)

            Divider()

            Button(String(localized: "report.export.allActive")) {
                commandActions?.exportAllActiveMetersReport?()
            }
            .disabled(commandActions?.exportAllActiveMetersReport == nil)

            Button(String(localized: "report.print.allActive")) {
                commandActions?.printAllActiveMetersReport?()
            }
            .disabled(commandActions?.printAllActiveMetersReport == nil)
        }

        CommandGroup(replacing: .help) {
            Button(String(localized: "update.check")) {
                updateService.checkForUpdates()
            }
            .disabled(updateService.isBusy)

            Divider()

            Button(String(localized: "help.shortcuts")) {
                commandActions?.showHelp()
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
            .disabled(commandActions == nil)
        }
    }
}
