import SwiftUI
import AppKit

enum InterfaceStyle: String, CaseIterable, Identifiable {
    case liquidGlass, classic
    var id: String { rawValue }
    var title: String { self == .liquidGlass ? "Liquid Glass" : "简洁" }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, mint, violet, orange
    var id: String { rawValue }
    var title: String {
        switch self { case .blue: return "蓝色"; case .mint: return "薄荷"; case .violet: return "紫色"; case .orange: return "橙色" }
    }
    var color: Color {
        switch self { case .blue: return .blue; case .mint: return .mint; case .violet: return .purple; case .orange: return .orange }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults: UserDefaults
    @Published var style: InterfaceStyle { didSet { defaults.set(style.rawValue, forKey: "interfaceStyle") } }
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearanceMode") } }
    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accentChoice") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = InterfaceStyle(rawValue: defaults.string(forKey: "interfaceStyle") ?? "") ?? .liquidGlass
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system
        accent = AccentChoice(rawValue: defaults.string(forKey: "accentChoice") ?? "") ?? .blue
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case computers = "所有会话", favorites = "收藏", history = "历史会话", settings = "设置"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .computers: return "rectangle.stack"
        case .favorites: return "star"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class WorkspaceNavigation: ObservableObject {
    @Published var section: WorkspaceSection = .computers
}

private struct NavigationSurface: ViewModifier {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if settings.style == .liquidGlass && !reduceTransparency {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
            } else {
                content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
            }
        } else {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.08)))
        }
    }
}

extension View {
    func navigationSurface(radius: CGFloat = 16) -> some View { modifier(NavigationSurface(radius: radius)) }
}

struct WorkspaceBackground: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if settings.style == .liquidGlass && !reduceTransparency {
                LinearGradient(colors: [settings.accent.color.opacity(0.12), .clear, settings.accent.color.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.ignoresSafeArea()
    }
}
