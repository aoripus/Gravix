import SwiftUI
import AppKit

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
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearanceMode") } }
    @Published var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accentChoice") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

enum SidebarSelection: Hashable {
    case section(WorkspaceSection)
    case profile(UUID)
}

@MainActor
final class WorkspaceNavigation: ObservableObject {
    @Published var selection: SidebarSelection? = .section(.computers)
    var section: WorkspaceSection {
        get {
            if case let .section(section) = selection { return section }
            return .computers
        }
        set { selection = .section(newValue) }
    }
}

// Use Apple's primitive button styles, including their native interaction effects.
// The availability branch keeps macOS 14/15 builds usable with standard controls.
private struct NativeGlassButton: ViewModifier {
    var prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func nativeGlassButton(prominent: Bool = false) -> some View {
        modifier(NativeGlassButton(prominent: prominent))
    }
}

struct NativeGlassControls<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
    }
}
