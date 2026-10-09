import SwiftUI
import AppKit

extension Notification.Name { static let newGravixConnection = Notification.Name("newGravixConnection") }

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: SessionManager?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sessions?.stopAll()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct GravixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ConnectionStore()
    @StateObject private var sessions = SessionManager()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var navigation = WorkspaceNavigation()
    var body: some Scene {
        Window("Gravix", id: "main") {
            ContentView().environmentObject(store).environmentObject(sessions)
                .environmentObject(settings).environmentObject(navigation)
                .preferredColorScheme(settings.appearance.colorScheme)
                .onAppear { delegate.sessions = sessions; settings.applyAppearance() }
                .onChange(of: settings.appearance) { _, _ in settings.applyAppearance() }
        }.defaultSize(width: 1140, height: 740)
            .windowStyle(.titleBar)
            .windowToolbarStyle(.unified)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("新建会话…") { NotificationCenter.default.post(name: .newGravixConnection, object: nil) }.keyboardShortcut("n")
                }
                WorkspaceCommands(navigation: navigation)
                CommandGroup(replacing: .help) {}
            }
    }
}

private struct WorkspaceCommands: Commands {
    @ObservedObject var navigation: WorkspaceNavigation
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { navigation.section = .settings; openWindow(id: "main") }
                .keyboardShortcut(",")
        }
    }
}
