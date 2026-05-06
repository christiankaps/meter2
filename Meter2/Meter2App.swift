import SwiftUI

@main
struct Meter2App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(
            width: AppConfiguration.defaultWindowWidth,
            height: AppConfiguration.defaultWindowHeight
        )
    }
}
