import SwiftUI
import SwiftData

@main
struct Meter2App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
    }
}
