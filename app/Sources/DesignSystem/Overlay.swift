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
                // The drawn circle and its layout stay as they were; only the
                // hit area grows to the 44pt minimum.
                .contentShape(Rectangle().inset(by: -max(0, (44 - size) / 2)))
        }
        .buttonStyle(.bouncy)   // springy press + gentle pointer-hover lift
        .accessibilityLabel(defaultLabel)
    }

    /// Icon-only, so VoiceOver needs words. Callers can still override with
    /// their own `.accessibilityLabel`.
    private var defaultLabel: String {
        let language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .ko
        switch systemName {
        case "xmark": return L.close[language]
        case "chevron.left": return L.back[language]
        case "gearshape": return L.settings[language]
        default: return systemName
        }
    }
}

/// The shared top bar for a pushed screen (dictionaries): a centered title with
/// a back button on the left, capped to the content width.
public struct NavHeader<Trailing: View>: View {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let title: String
    private let onBack: () -> Void
    private let trailing: Trailing

    public init(title: String, onBack: @escaping () -> Void,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        ZStack {
            Text(title)
                .font(.kawaii(17, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            HStack {
                CircleButton("chevron.left", size: 34, action: onBack)
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        .readableWidth(sizeClass)
    }
}

/// A rounded search field — used in the dictionaries so search sits within the
/// capped content width (not the full-width system search bar).
public struct SearchField: View {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @Binding private var text: String
    private let placeholder: String

    public init(text: Binding<String>, placeholder: String) {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.inkSoft)
            TextField(placeholder, text: $text)
                .font(.kawaii(15, language: appLanguage))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Palette.inkSoft.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.clearSearch[appLanguage])
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.card).clipShape(Capsule())
        .overlay(Capsule().stroke(Palette.ink.opacity(0.06), lineWidth: 1))
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
