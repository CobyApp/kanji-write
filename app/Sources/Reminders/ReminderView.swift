import ComposableArchitecture
import SwiftUI

public struct ReminderView: View {
    @Bindable public var store: StoreOf<ReminderFeature>
    @AppStorage("reminderEnabled") private var enabled = false
    @AppStorage("reminderHour") private var hour = 20

    public init(store: StoreOf<ReminderFeature>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("リマインダー") {
                Toggle("毎日のリマインダー", isOn: $enabled)
                if enabled {
                    Picker("時刻", selection: $hour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                }
                if store.authorizationDenied {
                    Text("通知が許可されていません。設定アプリで許可してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("設定")
        .task { store.send(.apply(enabled: enabled, hour: hour)) }
        .onChange(of: enabled) { _, newValue in
            store.send(.apply(enabled: newValue, hour: hour))
        }
        .onChange(of: hour) { _, newValue in
            store.send(.apply(enabled: enabled, hour: newValue))
        }
    }
}
