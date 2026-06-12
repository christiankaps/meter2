import SwiftUI

extension MeterKind {
    var tintColor: Color {
        switch self {
        case .electricity:
            Color.yellow
        case .gas:
            Color.orange
        case .water:
            Color.blue
        case .heat:
            Color.red
        case .solar:
            Color.green
        case .custom:
            Color.teal
        }
    }

    var subtleTintColor: Color {
        tintColor.opacity(0.12)
    }

    var subtleStrokeColor: Color {
        tintColor.opacity(0.28)
    }
}
