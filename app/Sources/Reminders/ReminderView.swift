import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct ReminderView: View {
    @Bindable public var store: StoreOf<ReminderFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("reminderEnabled") private var enabled = false
    @AppStorage("reminderHour") private var hour = 20
    @State private var showResetConfirm = false

    public init(store: StoreOf<ReminderFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    languageCard
                    reminderCard
                    resetCard
                }
                .padding(16)
            }
        }
        .navigationTitle(L.settings[appLanguage])
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            L.resetProgress[appLanguage], isPresented: $showResetConfirm, titleVisibility: .visible
        ) {
            Button(L.reset[appLanguage], role: .destructive) { store.send(.resetProgress) }
            Button(L.cancel[appLanguage], role: .cancel) {}
        } message: {
            Text(L.resetProgressMessage[appLanguage])
        }
        .task { store.send(.apply(enabled: enabled, hour: hour)) }
        .onChange(of: enabled) { _, newValue in
            store.send(.apply(enabled: newValue, hour: hour))
        }
        .onChange(of: hour) { _, newValue in
            store.send(.apply(enabled: enabled, hour: newValue))
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.language[appLanguage], accent: Palette.lavender)
            Picker("Language", selection: $appLanguage) {
                ForEach(AppLanguage.displayOrder, id: \.self) { language in
                    Text(language.label).tag(language)
                }
            }
            .pickerStyle(.segmented)
        }
        .roundedCard()
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.reminder[appLanguage], accent: Palette.pink)
            Toggle(L.dailyReminder[appLanguage], isOn: $enabled)
                .font(.kawaii(16)).tint(Palette.accent)
            if enabled {
                Picker(L.time[appLanguage], selection: $hour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                .font(.kawaii(16))
            }
            if store.authorizationDenied {
                Text(L.notifDenied[appLanguage])
                    .font(.kawaii(13)).foregroundStyle(Palette.inkSoft)
            }
        }
        .roundedCard()
    }

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.resetProgress[appLanguage], accent: Palette.pink)
            Button(role: .destructive) { showResetConfirm = true } label: {
                Text(L.resetProgress[appLanguage])
                    .font(.kawaii(16, weight: .bold)).foregroundStyle(Palette.pink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Palette.pinkSoft).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .roundedCard()
    }
}
