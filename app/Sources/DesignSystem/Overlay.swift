import SharedModels
import SwiftUI

/// A round icon button — the app's single style for top-corner actions (close ✕,
/// settings ⚙). Plain in-hierarchy button so it responds reliably everywhere,
/// including Mac Catalyst.
public struct CircleButton: View {
    private let systemName: String
    private let size: CGFloat
    private let action: () -> Void

    public init(_ systemName: String, size: CGFloat = 38, action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: size, height: size)
                .background(Palette.card, in: Circle())
                .shadow(color: Palette.ink.opacity(0.06), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// The shared top bar for every full-screen popup (study plan, settings): a
/// centered title with the close ✕ on the left — one consistent layout.
public struct OverlayHeader: View {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let title: String
    private let onClose: () -> Void

    public init(title: String, onClose: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(.kawaii(17, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            HStack {
                CircleButton("xmark", size: 34, action: onClose)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        // Keep the ✕ / title aligned to the capped content width, not the screen
        // edge, so they line up with the body on wide iPad / Mac windows.
        .readableWidth(sizeClass)
        .background(Palette.background)
    }
}
