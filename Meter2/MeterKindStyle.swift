import SwiftUI

extension MeterKind {
    var tintColor: Color {
        switch self {
        case .electricity:
            Color(red: 0.66, green: 0.43, blue: 0.05)
        case .gas:
            Color(red: 0.78, green: 0.30, blue: 0.08)
        case .water:
            Color(red: 0.12, green: 0.41, blue: 0.74)
        case .heat:
            Color(red: 0.72, green: 0.20, blue: 0.18)
        case .solar:
            Color(red: 0.16, green: 0.49, blue: 0.27)
        case .custom:
            Color(red: 0.04, green: 0.47, blue: 0.50)
        }
    }

    var subtleTintColor: Color {
        tintColor.opacity(0.12)
    }
}

/// A shared, low-emphasis container for Meter2 information groups.
struct MeterSurfaceModifier: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.07))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.09), lineWidth: 1)
                }
        }
    }
}

extension View {
    func meterSurface(tint: Color? = nil, cornerRadius: CGFloat = 12) -> some View {
        modifier(MeterSurfaceModifier(tint: tint, cornerRadius: cornerRadius))
    }
}
