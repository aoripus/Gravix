import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("外观") {
                LabeledContent("界面材质") {
                    if #available(macOS 26.0, *) { Text("Liquid Glass") }
                    else { Text("系统材质") }
                }
                Picker("主题", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                    .accessibilityIdentifier("appearance-picker")
                Picker("强调色", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { accent in
                        Label { Text(accent.title) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(accent.color)
                        }.tag(accent)
                    }
                }.accessibilityIdentifier("accent-picker")
            }
            Section("关于") {
                LabeledContent("Gravix", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                LabeledContent("开源软件") {
                    Button("查看许可") {
                        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") { NSWorkspace.shared.open(url) }
                    }.nativeGlassButton()
                }
            }
        }.formStyle(.grouped)
            .navigationTitle("设置")
            .accessibilityIdentifier("settings-page")
    }
}
