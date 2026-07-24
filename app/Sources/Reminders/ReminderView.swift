import ComposableArchitecture
import DesignSystem
import SharedModels
import SwiftUI

public struct ReminderView: View {
    @Bindable public var store: StoreOf<ReminderFeature>
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("studyStartIndex") private var studyStartIndex = 0
    @AppStorage("reminderEnabled") private var enabled = false
    @AppStorage("reminderHour") private var hour = 20
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showResetConfirm = false

    public init(store: StoreOf<ReminderFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    examCard
                    languageCard
                    reminderCard
                    resetCard
                }
                .padding(16)
                .readableWidth(sizeClass)
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

    /// Exam target: JLPT or 漢検. Switching resets the plan's level/range so it
    /// always points at a valid level for the chosen exam.
    private var examCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(L.examType[appLanguage], accent: Palette.sky)
            Picker("Exam", selection: $examType) {
                Text("JLPT").tag(ExamType.jlpt)
                Text("漢検").tag(ExamType.kanken)
            }
            .pickerStyle(.segmented)
        }
        .roundedCard()
        .onChange(of: examType) { _, newExam in
            targetLevel = newExam.defaultLevel
            studyStartIndex = 0
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
