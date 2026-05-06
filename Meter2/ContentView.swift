import AppKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .frame(
                minWidth: AppConfiguration.defaultWindowWidth,
                minHeight: AppConfiguration.defaultWindowHeight
            )
    }
}
