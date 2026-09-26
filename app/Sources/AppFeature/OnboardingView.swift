import DesignSystem
import SharedModels
import SwiftUI

/// First-run setup: explanation language, exam, starting level and daily pace.
/// Before this, a new install silently started in Korean on JLPT N5 at 7 a day,
/// and a 漢検 learner had to find the gear button to discover the other exam.
struct OnboardingView: View {
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .ko
    @AppStorage("examType") private var examType: ExamType = .jlpt
    @AppStorage("targetLevel") private var targetLevel = "N5"
    @AppStorage("newPerDay") private var newPerDay = 7
    @AppStorage("studyStartIndex") private var studyStartIndex = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    let onFinish: () -> Void

    /// The device's language when the app supports it — the app used to
    /// assume Korean for everyone.
    static var deviceLanguage: AppLanguage {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier ?? ""
            if let language = AppLanguage(rawValue: code) { return language }
        }
        return .en
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("漢")
                            .font(.kawaiiJP(52, weight: .bold)).japaneseGlyphs()
                            .foregroundStyle(.white)
                            .frame(width: 84, height: 84)
                            .background(LinearGradient(colors: [Palette.accent, Palette.lavender],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .accessibilityHidden(true)
                        Text(L.onboardingWelcome[appLanguage])
                            .font(.kawaii(26, weight: .bold, language: appLanguage))
                            .foregroundStyle(Palette.ink)
                        Text(L.onboardingIntro[appLanguage])
                            .font(.kawaii(15, language: appLanguage))
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    step(L.onboardingLanguage[appLanguage]) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(AppLanguage.displayOrder, id: \.self) { language in
                                choiceButton(language.label, selected: appLanguage == language) {
                                    appLanguage = language
                                }
                            }
                        }
                    }

                    step(L.onboardingExam[appLanguage]) {
                        VStack(spacing: 10) {
                            examButton(.jlpt, title: "JLPT", subtitle: L.examJLPTDesc[appLanguage])
                            examButton(.kanken, title: "漢検", subtitle: L.examKankenDesc[appLanguage])
                        }
                    }

                    step(L.onboardingLevel[appLanguage]) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                            ForEach(examType.levels, id: \.self) { level in
                                choiceButton(level, selected: targetLevel == level, japanese: true) {
                                    targetLevel = level
                                }
                            }
                        }
                    }

                    step(L.onboardingPerDay[appLanguage]) {
                        HStack(spacing: 8) {
                            ForEach([3, 5, 7, 10, 15], id: \.self) { count in
                                choiceButton("\(count)", selected: newPerDay == count) {
                                    newPerDay = count
                                }
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        Button {
                            studyStartIndex = 0
                            onFinish()
                        } label: {
                            Text(L.onboardingStart[appLanguage])
                                .font(.kawaii(18, weight: .bold, language: appLanguage))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Palette.accent).clipShape(Capsule())
                        }
                        .buttonStyle(.bouncy)
                        Text(L.onboardingLater[appLanguage])
                            .font(.kawaii(12, language: appLanguage)).foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .readableWidth(sizeClass)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: examType) { _, exam in
            if !exam.levels.contains(targetLevel) { targetLevel = exam.defaultLevel }
        }
    }

    private func step<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.kawaii(15, weight: .bold, language: appLanguage))
                .foregroundStyle(Palette.ink)
            content()
        }
        .roundedCard()
    }

    private func choiceButton(_ title: String, selected: Bool, japanese: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(japanese ? .kawaiiJP(16, weight: .bold) : .kawaii(16, weight: .bold, language: appLanguage))
                .foregroundStyle(selected ? .white : Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Palette.accent : Palette.background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : Palette.ink.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.bouncy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func examButton(_ exam: ExamType, title: String, subtitle: String) -> some View {
        let selected = examType == exam
        return Button { examType = exam } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.kawaiiJP(20, weight: .bold)).japaneseGlyphs()
                    .foregroundStyle(selected ? .white : Palette.accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 64, height: 48)
                    .background(selected ? Palette.accent : Palette.pinkSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(subtitle)
                    .font(.kawaii(14, language: appLanguage)).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(selected ? Palette.accent : Palette.inkSoft)
            }
            .padding(12)
            .background(selected ? Palette.pinkSoft.opacity(0.6) : Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.bouncy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
