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
    var body: some Scene {
        Window("Gravix", id: "main") {
            ContentView().environmentObject(store).environmentObject(sessions)
                .preferredColorScheme(.dark)
                .onAppear { delegate.sessions = sessions }
        }.defaultSize(width: 1080, height: 730)
            .windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("添加电脑…") { NotificationCenter.default.post(name: .newGravixConnection, object: nil) }.keyboardShortcut("n")
                }
                CommandGroup(replacing: .help) {
                    Button("Gravix 使用说明") { if let url = Bundle.main.url(forResource: "使用说明", withExtension: "txt") { NSWorkspace.shared.open(url) } }
                }
            }
    }
}
