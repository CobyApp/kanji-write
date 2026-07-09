import SwiftUI

extension View {
    /// Caps content to a comfortable reading width (compact 560 / regular 900),
    /// centered — so screens don't stretch edge-to-edge on iPad / Mac. Apply to
    /// the scrolling content, never to the full-bleed background.
    public func readableWidth(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        frame(maxWidth: sizeClass == .compact ? 560 : 900)
            .frame(maxWidth: .infinity)
    }
}
