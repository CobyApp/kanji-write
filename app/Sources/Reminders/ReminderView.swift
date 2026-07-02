import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct ReminderView: View {
    @Bindable public var store: StoreOf<ReminderFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("reminderEnabled") private var enabled = false
    @AppStorage("reminderHour") private var hour = 20

    public init(store: StoreOf<ReminderFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    studyCard
                    languageCard
                    reminderCard
                }
                .padding(16)
            }
        }
        .navigationTitle(L.settings[appLanguage])
        .task { store.send(.apply(enabled: enabled, hour: hour)) }
        .onChange(of: enabled) { _, newValue in
            store.send(.apply(enabled: newValue, hour: hour))
        }
        .onChange(of: hour) { _, newValue in
            store.send(.apply(enabled: enabled, hour: newValue))
        }
    }

    private var studyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.study[appLanguage], accent: Palette.butter)
            Stepper(value: $newPerDay, in: 1...30) {
                Text("\(L.newPerDay[appLanguage]): \(newPerDay)")
                    .font(.kawaii(16)).foregroundStyle(Palette.ink)
            }
            .tint(Palette.accent)
        }
        .roundedCard()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.language[appLanguage], accent: Palette.lavender)
            Picker("Language", selection: $appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
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
}
