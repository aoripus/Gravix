import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("外观").font(.system(size: 24, weight: .semibold))
                    Text("让工作空间更适合你。").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("界面风格").font(.headline)
                    HStack(spacing: 16) {
                        ForEach(InterfaceStyle.allCases) { style in
                            Button { settings.style = style } label: { themePreview(style) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(style.title)
                                .accessibilityValue(settings.style == style ? "已选中" : "未选中")
                                .accessibilityIdentifier("theme-\(style.rawValue)")
                        }
                    }
                    if #unavailable(macOS 26.0) {
                        Text("当前系统使用磨砂材质；macOS 26 及以上使用原生 Liquid Glass。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    HStack {
                        Label("显示模式", systemImage: "circle.lefthalf.filled")
                        Spacer()
                        Picker("显示模式", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 260)
                    }.padding(20)
                    Divider().padding(.horizontal, 20)
                    HStack {
                        Label("强调色", systemImage: "paintpalette")
                        Spacer()
                        ForEach(AccentChoice.allCases) { accent in
                            Button { settings.accent = accent } label: {
                                Circle().fill(accent.color.gradient).frame(width: 28, height: 28)
                                    .overlay {
                                        if settings.accent == accent {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .padding(4).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(accent.title)
                                .accessibilityLabel(accent.title)
                                .accessibilityValue(settings.accent == accent ? "已选中" : "未选中")
                        }
                    }.padding(20)
                }.background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Gravix").font(.headline)
                        Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("开源许可") {
                        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") { NSWorkspace.shared.open(url) }
                    }
                }.padding(.top, 8)
            }.padding(28).frame(maxWidth: 760).frame(maxWidth: .infinity, alignment: .topLeading)
        }.accessibilityIdentifier("settings-page")
    }

    private func themePreview(_ style: InterfaceStyle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { _ in Circle().fill(.secondary.opacity(0.3)).frame(width: 4, height: 4) }
                    }.padding(.bottom, 6)
                    RoundedRectangle(cornerRadius: 3).fill(settings.accent.color.opacity(0.3)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.13)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.13)).frame(height: 6)
                    Spacer(minLength: 0)
                }.padding(10).frame(width: 65).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(0.06)).frame(height: 15)
                    ForEach(0..<3) { _ in
                        HStack(spacing: 6) {
                            Image(systemName: "desktopcomputer").font(.system(size: 9)).foregroundStyle(settings.accent.color)
                            RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.18)).frame(height: 4)
                            Spacer(minLength: 8)
                        }.padding(7).background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }.padding(14).frame(height: 150)
                .background(style == .liquidGlass ? settings.accent.color.opacity(0.14) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text(style.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: settings.style == style ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(settings.style == style ? settings.accent.color : .secondary)
            }
            Text(style == .liquidGlass ? "通透材质，轻盈层次" : "纯色面板，专注内容")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(settings.style == style ? settings.accent.color : .primary.opacity(0.08), lineWidth: settings.style == style ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
