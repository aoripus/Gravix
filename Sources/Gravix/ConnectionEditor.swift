import SwiftUI
import AppKit

struct ConnectionEditor: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State var profile: ConnectionProfile
    @State private var password = ""
    @State private var error = ""
    @State private var loaded = false
    let isNew: Bool
    let onSave: (ConnectionProfile, String, Bool) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(settings.accent.color.opacity(0.13)); Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(settings.accent.color) }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "新建 RDP 会话" : "编辑连接").font(.title2.bold())
                    Text("Windows 远程桌面").foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section("连接") {
                    TextField("名称", text: $profile.name, prompt: Text("例如：办公室电脑"))
                    TextField("电脑地址", text: $profile.host, prompt: Text("192.168.1.100 或主机名"))
                    TextField("端口", value: $profile.port, format: .number.grouping(.never))
                    TextField("用户名", text: $profile.username, prompt: Text("Windows 用户名"))
                    TextField("域（可选）", text: $profile.domain, prompt: Text("留空即可"))
                    SecureField("密码", text: $password, prompt: Text("Windows 账户密码，不是 PIN"))
                    Toggle("在 macOS 钥匙串中记住密码", isOn: $profile.rememberPassword)
                }
                Section("显示与性能") {
                    Toggle("优先使用硬件解码", isOn: $profile.hardwareAcceleration)
                    Text("通过 VideoToolbox 解码 H.264；Windows 需要支持并协商该格式。").font(.caption).foregroundStyle(.secondary)
                    Toggle("分辨率随窗口自动调整", isOn: $profile.dynamicResolution)
                    Toggle("使用 Retina 像素分辨率", isOn: $profile.retina).disabled(!profile.dynamicResolution)
                    if !profile.dynamicResolution {
                        HStack { TextField("宽", value: $profile.width, format: .number.grouping(.never)); Text("×"); TextField("高", value: $profile.height, format: .number.grouping(.never)) }
                    }
                }
                Section("剪贴板与文件") {
                    Toggle("同步文字与文件剪贴板", isOn: $profile.clipboard)
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("共享文件夹")
                            Text(profile.sharedFolder.isEmpty ? "仅共享你选择的文件夹" : profile.sharedFolder).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if !profile.sharedFolder.isEmpty { Button("移除") { profile.sharedFolder = "" } }
                        Button("选择…") { chooseFolder() }
                    }
                    if !profile.sharedFolder.isEmpty { Text("Windows 资源管理器中访问 \\\\tsclient\\Gravix（可读写）。").font(.caption).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { submit(connect: false) }
                Button("保存并连接") { submit(connect: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 570, height: 730)
        .onAppear {
            guard !loaded else { return }; loaded = true
            do { password = try PasswordVault.read(profile.id) ?? "" }
            catch { self.error = error.localizedDescription }
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Windows 会话可读写这个文件夹。"
        if panel.runModal() == .OK, let url = panel.url { profile.sharedFolder = url.path }
    }
    private func submit(connect: Bool) {
        profile.normalize()
        do { try onSave(profile, password, connect); password = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct PasswordPrompt: View {
    @Environment(\.dismiss) private var dismiss
    let profile: ConnectionProfile
    let connect: (String) -> Void
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(profile.title, systemImage: "lock.shield").font(.title2.bold())
            Text("\(profile.account) · \(profile.endpoint)").foregroundStyle(.secondary)
            SecureField("Windows 密码（不是 PIN）", text: $password).textFieldStyle(.roundedBorder)
            Text("此密码仅用于本次连接。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("连接") { connect(password); password = ""; dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 420)
    }
}
