import SwiftUI

/// A viewport alpha mask blends scrolling text into its existing surface.
/// Matching content insets keep the first and last lines fully readable.
struct ScrollEdgeFade: View {
    let length: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(0.5, max(0, length) / max(1, geometry.size.height))
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fraction),
                .init(color: .black, location: 1 - fraction),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
