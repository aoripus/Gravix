import SwiftUI
import AppKit

@MainActor
final class RemoteSession: ObservableObject {
    let id = UUID()
    let profile: ConnectionProfile
    let bridge: GRSession
    let recordID: UUID
    weak var store: ConnectionStore?
    @Published var state = "connecting"
    @Published var error = ""
    @Published var transfer = ""
    @Published var remoteFilesReady = false
    @Published var receivedFolder: URL?
    var connectedAt: Date?
    var isLive: Bool { state == "connecting" || state == "connected" }

    init(profile: ConnectionProfile, password: String, store: ConnectionStore) {
        self.profile = profile
        self.store = store
        recordID = store.begin(profile)
        bridge = GRSession(configuration: [
            "host": profile.host, "port": profile.port, "username": profile.username,
            "domain": profile.domain, "hardware": profile.hardwareAcceleration,
            "clipboard": profile.clipboard, "dynamic": profile.dynamicResolution,
            "retina": profile.retina, "width": profile.width, "height": profile.height,
            "share": profile.sharedFolder
        ], password: password)
        bridge.eventHandler = { [weak self] event, detail in
            guard let self else { return }
            switch event {
            case "state":
                self.state = detail
                if detail == "connected" { self.connectedAt = Date(); self.store?.connected(self.recordID); self.bridge.desktopView.scheduleInitialFocus() }
                if detail == "disconnected" { self.store?.ended(self.recordID, outcome: self.connectedAt == nil ? "已取消" : "已断开") }
            case "error": self.error = detail; self.state = "failed"; self.store?.ended(self.recordID, outcome: "连接失败")
            case "transfer": self.transfer = detail
            case "remoteFiles": self.remoteFilesReady = detail == "ready"
            case "received":
                let url = URL(fileURLWithPath: detail, isDirectory: true)
                self.receivedFolder = url
                self.transfer = "接收完成，可以在 Finder 中粘贴文件。"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            default: break
            }
        }
    }
    func stop() {
        bridge.stop()
        store?.ended(recordID, outcome: connectedAt == nil ? "已取消" : "已断开")
        state = "disconnected"
    }
    func sendFiles() {
        let panel = NSOpenPanel()
        panel.message = "选择文件后，在 Windows 文件夹内按 ⌘V 粘贴。"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        bridge.publishFiles(panel.urls)
        bridge.desktopView.window?.makeFirstResponder(bridge.desktopView)
    }
    func receiveFiles() {
        let panel = NSOpenPanel()
        panel.message = "选择 Windows 剪贴板文件的接收位置。"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bridge.receiveFiles(at: url)
    }
}

extension GRDesktopView {
    func scheduleInitialFocus() {
        window?.makeFirstResponder(self)
        // Trigger the first layout after the display-control channel connects.
        setFrameSize(frame.size)
    }
}

@MainActor
final class RemoteWindow: NSObject, NSWindowDelegate {
    let session: RemoteSession
    let window: NSWindow
    var onClose: (() -> Void)?
    init(session: RemoteSession) {
        self.session = session
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(session.profile.title) — Gravix"
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RemoteSessionView(session: session).environmentObject(AppSettings.shared))
        window.center(); window.makeKeyAndOrderFront(nil)
        session.bridge.start()
    }
    func windowWillClose(_ notification: Notification) { session.stop(); onClose?() }
    func windowDidResignKey(_ notification: Notification) {
        // Resigning first responder releases remote modifiers, avoiding stuck Ctrl/Shift.
        window.makeFirstResponder(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { window.makeFirstResponder(session.bridge.desktopView) }
}

@MainActor
final class SessionManager: ObservableObject {
    @Published var windows: [UUID: RemoteWindow] = [:]
    var count: Int { windows.values.filter { $0.session.isLive }.count }
    func connect(_ profile: ConnectionProfile, password: String, store: ConnectionStore) {
        let session = RemoteSession(profile: profile, password: password, store: store)
        let remote = RemoteWindow(session: session)
        remote.onClose = { [weak self] in self?.windows.removeValue(forKey: session.id) }
        windows[session.id] = remote
    }
    func stopAll() { for remote in windows.values { remote.session.stop() } }
}

struct RemoteDesktop: NSViewRepresentable {
    let session: RemoteSession
    func makeNSView(context: Context) -> GRDesktopView { session.bridge.desktopView }
    func updateNSView(_ view: GRDesktopView, context: Context) {}
}

struct RemoteSessionView: View {
    @ObservedObject var session: RemoteSession
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(session.state == "connected" ? Color.mint : Color.orange).frame(width: 7, height: 7)
                Text(session.profile.title).font(.headline)
                Text(session.profile.endpoint).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button { session.sendFiles() } label: { Label("发送文件", systemImage: "square.and.arrow.up") }
                    .disabled(session.state != "connected" || !session.profile.clipboard)
                Button { session.receiveFiles() } label: { Label("接收文件", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(!session.remoteFilesReady || session.state != "connected" || !session.profile.clipboard)
                Menu {
                    Button("发送 Ctrl + Alt + Delete") { session.bridge.sendControlAltDelete() }
                    Button("切换全屏") { session.bridge.desktopView.window?.toggleFullScreen(nil) }
                    if !session.profile.sharedFolder.isEmpty {
                        Button("打开 Mac 共享文件夹") { NSWorkspace.shared.open(URL(fileURLWithPath: session.profile.sharedFolder)) }
                        Button("复制 Windows 共享路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\\\\tsclient\\Gravix", forType: .string) }
                    }
                    Button("取消文件接收") { session.bridge.cancelTransfer() }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                Button("断开") { session.stop() }.disabled(!session.isLive)
            }.padding(.horizontal, 14).padding(.vertical, 10).navigationSurface(radius: 12).padding(8)
            Divider()
            ZStack {
                RemoteDesktop(session: session)
                if session.state != "connected" {
                    Color(nsColor: .windowBackgroundColor)
                    VStack(spacing: 18) {
                        if session.state == "connecting" { ProgressView().controlSize(.large) }
                        else { Image(systemName: session.state == "failed" ? "wifi.exclamationmark" : "display").font(.system(size: 44)).foregroundStyle(.secondary) }
                        Text(session.state == "connecting" ? "正在连接 Windows…" : session.state == "failed" ? "连接未成功" : "会话已结束").font(.title2.bold())
                        Text(session.error.isEmpty ? session.profile.endpoint : session.error).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                        if session.state == "connecting" { Button("取消连接") { session.stop() } }
                        else { Text("回到主窗口，双击电脑即可重新连接。").font(.callout).foregroundStyle(.secondary) }
                    }.padding(40)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Label(session.profile.hardwareAcceleration ? "VideoToolbox 优先" : "软件解码", systemImage: "cpu")
                    .help("启用硬件解码；实际使用取决于 Windows 协商的编码格式和设备支持，失败时由解码器回退。")
                Text("·")
                Text(session.profile.dynamicResolution ? "分辨率随窗口调整" : "\(session.profile.width) × \(session.profile.height)")
                Spacer()
                Text(session.transfer.isEmpty ? "⌘C / ⌘V 复制粘贴 · ⌘⇧V 接收 Windows 文件" : session.transfer).lineLimit(1)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        }.frame(minWidth: 640, minHeight: 440)
            .background { WorkspaceBackground() }
            .tint(settings.accent.color)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}
