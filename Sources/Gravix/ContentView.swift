import SwiftUI
import AppKit

private enum SectionID: String, CaseIterable { case computers = "我的电脑", history = "历史会话", help = "使用帮助" }
private struct EditorDraft: Identifiable { let id = UUID(); let profile: ConnectionProfile; let isNew: Bool }

struct ContentView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var sessions: SessionManager
    @State private var section: SectionID = .computers
    @State private var search = ""
    @State private var draft: EditorDraft?
    @State private var passwordProfile: ConnectionProfile?
    @State private var deleteProfile: ConnectionProfile?
    @State private var confirmClear = false
    private let accent = Color(red: 0.43, green: 0.88, blue: 0.75)
    private var filtered: [ConnectionProfile] {
        store.profiles.filter { search.isEmpty || "\($0.title) \($0.host) \($0.username)".localizedCaseInsensitiveContains(search) }
            .sorted { if $0.favorite != $1.favorite { return $0.favorite }; return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if section == .computers { computers }
                        else if section == .history { history }
                        else { help }
                    }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 900, minHeight: 620)
        .tint(accent)
        .sheet(item: $draft) { draft in
            ConnectionEditor(profile: draft.profile, isNew: draft.isNew) { profile, password, connect in
                try store.upsert(profile, password: password)
                if connect { sessions.connect(profile, password: password, store: store) }
            }
        }
        .sheet(item: $passwordProfile) { profile in PasswordPrompt(profile: profile) { sessions.connect(profile, password: $0, store: store) } }
        .alert("删除这个连接？", isPresented: Binding(get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } })) {
            Button("取消", role: .cancel) { deleteProfile = nil }
            Button("删除", role: .destructive) { if let profile = deleteProfile { store.remove(profile) }; deleteProfile = nil }
        } message: { Text("保存的连接和钥匙串密码将被删除，历史记录会保留。") }
        .alert("清空历史会话？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.history.removeAll(); store.save() }
        } message: { Text("保存的电脑和密码不受影响。") }
        .alert("Gravix", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("好") { store.message = nil } } message: { Text(store.message ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .newGravixConnection)) { _ in newConnection() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(accent.gradient)
                    Image(systemName: "rectangle.connected.to.line.below").font(.system(size: 22, weight: .semibold)).foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.16))
                }.frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) { Text("Gravix").font(.system(size: 23, weight: .bold, design: .rounded)); Text("REMOTE DESKTOP").font(.system(size: 8, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary) }
            }.padding(.top, 31).padding(.bottom, 36).padding(.horizontal, 21)
            Text("工作空间").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.horizontal, 25).padding(.bottom, 12)
            ForEach(SectionID.allCases, id: \.self) { item in
                Button { section = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item == .computers ? "desktopcomputer" : item == .history ? "clock.arrow.circlepath" : "questionmark.circle").font(.system(size: 15)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 13, weight: section == item ? .semibold : .regular))
                        Spacer()
                        if item == .computers { Text("\(store.profiles.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }.foregroundStyle(section == item ? accent : .secondary).padding(.horizontal, 12).padding(.vertical, 12)
                        .background(section == item ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) { Circle().fill(accent).frame(width: 6, height: 6); Text("连接引擎已就绪").font(.system(size: 11, weight: .medium)) }
                Text("原生 macOS · Windows RDP").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).padding(16)
            Text("GRAVIX  /  0.1.0").font(.system(size: 9, design: .monospaced)).tracking(1.3).foregroundStyle(.tertiary).padding(.leading, 24).padding(.bottom, 20)
        }.background(Color(red: 0.085, green: 0.10, blue: 0.115))
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(section.rawValue).font(.system(size: 25, weight: .semibold))
                Text(section == .computers ? "连接你的 Windows，回到熟悉的工作桌面。" : section == .history ? "每次连接，都有迹可循。" : "从第一次连接，到顺手地跨设备工作。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if section == .computers {
                HStack(spacing: 7) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索电脑", text: $search).textFieldStyle(.plain) }
                    .padding(9).frame(width: 155).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                Button { newConnection() } label: { Label("添加电脑", systemImage: "plus").padding(.vertical, 4).padding(.horizontal, 3) }.buttonStyle(.borderedProminent).foregroundStyle(.black)
            }
        }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 24)
    }
    private var computers: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 14) {
                metric("已保存电脑", value: store.profiles.count, icon: "desktopcomputer")
                metric("会话窗口", value: sessions.windows.count, icon: "rectangle.on.rectangle")
                metric("历史连接", value: store.history.count, icon: "clock")
            }
            if store.profiles.isEmpty {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(accent.opacity(0.035)).frame(width: 170, height: 170)
                        Circle().stroke(accent.opacity(0.10), lineWidth: 1).frame(width: 138, height: 138)
                        Image(systemName: "desktopcomputer").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(accent)
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.black).frame(width: 28, height: 28).background(accent, in: Circle()).offset(x: 44, y: -30)
                    }
                    VStack(spacing: 9) {
                        Text("下一台桌面，近在眼前。").font(.system(size: 23, weight: .medium))
                        Text("添加 Windows 电脑，保存连接信息。\n之后只需一次点击，即可继续工作。").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    }
                    Button { newConnection() } label: { Label("添加第一台电脑", systemImage: "plus").padding(.horizontal, 15).padding(.vertical, 7) }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                    HStack(spacing: 22) { feature("硬件解码", icon: "cpu"); feature("钥匙串密码", icon: "lock.shield"); feature("文件互传", icon: "doc.on.doc") }.padding(.top, 18)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                HStack { Text("你的电脑").font(.headline); Spacer(); Text("双击卡片连接").font(.caption).foregroundStyle(.tertiary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 16)], spacing: 16) {
                    ForEach(filtered) { profile in connectionCard(profile) }
                }
            }
        }
    }
    private func metric(_ label: String, value: Int, icon: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); Text("\(value)").font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit() }
            Spacer(); Image(systemName: icon).font(.title3).foregroundStyle(.tertiary)
        }.padding(18).frame(maxWidth: .infinity).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.045)))
    }
    private func feature(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary) }
    private func connectionCard(_ profile: ConnectionProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "desktopcomputer").font(.system(size: 25)).foregroundStyle(accent).frame(width: 48, height: 48).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Button { store.favorite(profile) } label: { Image(systemName: profile.favorite ? "star.fill" : "star").foregroundStyle(profile.favorite ? .yellow : .secondary) }.buttonStyle(.plain).help("收藏")
                Menu { Button("编辑连接") { edit(profile) }; Button("删除连接", role: .destructive) { deleteProfile = profile } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 6) { Text(profile.title).font(.system(size: 17, weight: .semibold)).lineLimit(1); Text(profile.endpoint).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1); Text(profile.account).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
            Divider().opacity(0.5)
            HStack { Label(profile.hardwareAcceleration ? "硬件解码优先" : "软件解码", systemImage: "cpu").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("连接  ↗") { connect(profile) }.buttonStyle(.bordered).tint(accent) }
        }.padding(20).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.065)))
            .contentShape(Rectangle()).onTapGesture(count: 2) { connect(profile) }
            .contextMenu { Button("连接") { connect(profile) }; Button("编辑") { edit(profile) }; Button("删除", role: .destructive) { deleteProfile = profile } }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("最近 200 次连接").font(.caption).foregroundStyle(.secondary); Spacer(); Button("清空历史", role: .destructive) { confirmClear = true }.disabled(store.history.isEmpty) }
            if store.history.isEmpty { ContentUnavailableView("还没有连接记录", systemImage: "clock", description: Text("连接电脑后，会在这里记录时间和结果。")) }
            ForEach(store.history) { record in
                HStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").foregroundStyle(accent).frame(width: 32)
                    VStack(alignment: .leading, spacing: 5) { Text(record.title).font(.headline); Text(record.endpoint).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) { Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption); Text(record.duration).font(.caption).foregroundStyle(.secondary) }
                    Text(record.outcome).font(.caption).foregroundStyle(record.outcome == "连接失败" ? .orange : .secondary).frame(width: 80)
                    Button("再连接") { if let p = store.profiles.first(where: { $0.id == record.profileID }) { connect(p) } }.disabled(!store.profiles.contains { $0.id == record.profileID })
                }.padding(16).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var help: some View {
        VStack(alignment: .leading, spacing: 22) {
            helpBlock("01", "准备 Windows", "在 Windows 的“设置 → 系统 → 远程桌面”开启远程桌面。通常需要专业版、企业版或 Windows Server；家庭版不能作为内置 RDP 主机。Mac 与 Windows 需要网络可达。")
            helpBlock("02", "填写连接", "电脑地址填写 IP 或主机名，默认端口 3389。输入 Windows 用户名和账户密码，不能用 Windows Hello PIN。第一次连接时请核对证书指纹，再决定是否信任。")
            helpBlock("03", "复制文字和文件", "文字：两端正常复制粘贴。Mac → Windows 文件：在 Finder 中 ⌘C，进入远程文件夹按 ⌘V，也可以用“发送文件”按钮或把文件拖入远程窗口。Windows → Mac 文件：在 Windows 复制文件，点击“接收文件”或按 ⌘⇧V，选好保存位置；接收完成后也可以到 Finder 中 ⌘V。")
            helpBlock("04", "共享文件夹", "在连接设置中选择一个 Mac 文件夹。连接后，在 Windows 资源管理器的地址栏输入 \\\\tsclient\\Gravix，即可双向复制、编辑文件。共享仅限你选择的文件夹。")
            helpBlock("05", "画面与快捷键", "拖动远程窗口边缘会请求 Windows 调整桌面分辨率。硬件解码需要服务器协商 H.264；不支持时使用其他可用编码。⌘C / ⌘V / ⌘X / ⌘A 映射为 Windows 的 Ctrl 快捷键。工具栏“更多”可发送 Ctrl + Alt + Delete 或切换全屏。")
            Divider()
            Text(GRSession.engineVersion()).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("密码保存在本机钥匙串；电脑列表与历史记录保存在 Application Support/Gravix。应用不会上传这些资料。").font(.caption).foregroundStyle(.secondary)
            Button("查看开源许可") { if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") { NSWorkspace.shared.open(url) } }
        }
    }
    private func helpBlock(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 18) { Text(number).font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(accent).padding(.top, 2); VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true) } }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }
    private func newConnection() { draft = EditorDraft(profile: ConnectionProfile(), isNew: true) }
    private func edit(_ profile: ConnectionProfile) { draft = EditorDraft(profile: profile, isNew: false) }
    private func connect(_ profile: ConnectionProfile) {
        if let error = profile.validationError { store.message = error; return }
        do {
            if profile.rememberPassword, let password = try PasswordVault.read(profile.id) { sessions.connect(profile, password: password, store: store) }
            else { passwordProfile = profile }
        } catch { store.message = error.localizedDescription }
    }
}
