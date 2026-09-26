import SwiftUI
import OasisCore

/// The map pin for one water point: a round badge with a white symbol,
/// a white border, and a shadow. A small check mark marks a verified point.
/// Same design as the explorer icons.
struct SpotPin: View {
    let kind: SpotKind
    let verified: Bool
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: kind == .other ? size * 0.3 : size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(kind.tint))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) {
                if verified {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.28, weight: .heavy))
                        .foregroundStyle(Color.oasisInk)
                        .frame(width: size * 0.5, height: size * 0.5)
                        .background(Circle().fill(.white))
                        .overlay(Circle().stroke(Color.oasisInk.opacity(0.35), lineWidth: 0.5))
                        .offset(x: size * 0.2, y: -size * 0.2)
                }
            }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(SpotKind.allCases) { kind in
            SpotPin(kind: kind, verified: kind == .fountain)
        }
    }
    .padding()
    .background(Color(white: 0.9))
}
