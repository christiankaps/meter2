import SwiftData
import SwiftUI

@main
struct Meter2CompanionApp: App {
    @StateObject private var syncService = MeterLibrarySyncService()

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environmentObject(syncService)
        }
        .modelContainer(for: [
            Meter.self,
            MeterReading.self,
            MeterTariff.self,
            BillingPeriod.self
        ])
    }
}
