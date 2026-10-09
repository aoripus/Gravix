import SwiftUI
import AppKit

private struct EditorDraft: Identifiable { let id = UUID(); let profile: ConnectionProfile; let isNew: Bool }

struct ContentView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigation: WorkspaceNavigation
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var search = ""
    @State private var selectedProfileID: UUID?
    @State private var selectedRecordID: UUID?
    @State private var draft: EditorDraft?
    @State private var passwordProfile: ConnectionProfile?
    @State private var deleteProfile: ConnectionProfile?
    @State private var confirmClear = false

    private var sortedProfiles: [ConnectionProfile] {
        store.profiles.sorted {
            if $0.favorite != $1.favorite { return $0.favorite }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    private var filtered: [ConnectionProfile] {
        sortedProfiles.filter {
            (navigation.section != .favorites || $0.favorite) &&
            (search.isEmpty || "\($0.title) \($0.host) \($0.account)".localizedCaseInsensitiveContains(search))
        }
    }
    private var filteredHistory: [SessionRecord] {
        store.history.filter { search.isEmpty || "\($0.title) \($0.endpoint)".localizedCaseInsensitiveContains(search) }
    }
    private var selectedProfile: ConnectionProfile? { filtered.first { $0.id == selectedProfileID } }
    private var sessionWindows: [RemoteWindow] {
        sessions.windows.values.sorted { $0.session.profile.title.localizedStandardCompare($1.session.profile.title) == .orderedAscending }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle("Gravix")
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 320)
        } detail: {
            detail
                .navigationTitle(navigation.section.rawValue)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !sessionWindows.isEmpty { sessionStrip }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 580)
        .tint(settings.accent.color)
        .toolbar { workspaceToolbar }
        .sheet(item: $draft) { draft in
            ConnectionEditor(profile: draft.profile, isNew: draft.isNew) { profile, password, connect in
                try store.upsert(profile, password: password)
                navigation.selection = .profile(profile.id)
                selectedProfileID = profile.id
                if connect { sessions.connect(profile, password: password, store: store) }
            }
        }
        .sheet(item: $passwordProfile) { profile in
            PasswordPrompt(profile: profile) { sessions.connect(profile, password: $0, store: store) }
        }
        .alert("删除这个连接？", isPresented: Binding(get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } })) {
            Button("取消", role: .cancel) { deleteProfile = nil }
            Button("删除", role: .destructive) {
                if let profile = deleteProfile {
                    store.remove(profile)
                    if navigation.selection == .profile(profile.id) { navigation.section = .computers }
                    if selectedProfileID == profile.id { selectedProfileID = nil }
                }
                deleteProfile = nil
            }
        } message: { Text("保存的连接和钥匙串密码将被删除，历史记录会保留。") }
        .alert("清空历史会话？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.history.removeAll(); store.save() }
        } message: { Text("保存的电脑和密码不受影响。") }
        .alert("Gravix", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("好") { store.message = nil }
        } message: { Text(store.message ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .newGravixConnection)) { _ in newConnection() }
        .onChange(of: navigation.selection) { _, selection in
            search = ""
            if case let .profile(id) = selection { selectedProfileID = id }
        }
    }

    private var sidebar: some View {
        List(selection: $navigation.selection) {
            Section("会话") {
                Label("所有会话", systemImage: "rectangle.stack")
                    .badge(store.profiles.count)
                    .tag(SidebarSelection.section(.computers))
                    .accessibilityIdentifier("nav-computers")
                Label("收藏", systemImage: "star")
                    .badge(store.profiles.filter(\.favorite).count)
                    .tag(SidebarSelection.section(.favorites))
                    .accessibilityIdentifier("nav-favorites")
                Label("历史会话", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarSelection.section(.history))
                    .accessibilityIdentifier("nav-history")
            }
            if !sortedProfiles.isEmpty {
                Section("已保存") {
                    ForEach(sortedProfiles) { profile in
                        Label(profile.title, systemImage: "desktopcomputer")
                            .lineLimit(1)
                            .tag(SidebarSelection.profile(profile.id))
                            .contextMenu { profileActions(profile) }
                    }
                }
            }
            Section {
                Label("设置", systemImage: "gearshape")
                    .tag(SidebarSelection.section(.settings))
                    .accessibilityIdentifier("nav-settings")
            }
        }.listStyle(.sidebar)
    }

    @ViewBuilder private var detail: some View {
        switch navigation.section {
        case .computers, .favorites:
            computers.searchable(text: $search, prompt: "搜索会话")
        case .history:
            history.searchable(text: $search, prompt: "搜索历史")
        case .settings:
            SettingsView()
        }
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { newConnection() } label: { Label("新建会话", systemImage: "plus") }
                .nativeGlassButton(prominent: true).help("新建会话 (⌘N)")
        }
        if navigation.section == .computers || navigation.section == .favorites {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { if let selectedProfile { connect(selectedProfile) } } label: { Label("连接", systemImage: "play.fill") }
                    .disabled(selectedProfile == nil).help("连接选中的会话")
                Button { if let selectedProfile { edit(selectedProfile) } } label: { Label("编辑连接", systemImage: "pencil") }
                    .disabled(selectedProfile == nil).help("编辑选中的会话")
            }
        }
        if navigation.section == .history {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmClear = true } label: { Label("清空历史", systemImage: "trash") }
                    .disabled(store.history.isEmpty).help("清空历史")
            }
        }
    }

    @ViewBuilder private var computers: some View {
        if filtered.isEmpty {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView {
                    Label(navigation.section == .favorites ? "还没有收藏的会话" : "连接 Windows 电脑", systemImage: navigation.section == .favorites ? "star" : "desktopcomputer")
                } actions: {
                    if navigation.section == .favorites {
                        Button("查看所有会话") { navigation.section = .computers }.nativeGlassButton()
                    } else {
                        Button("新建会话") { newConnection() }.nativeGlassButton(prominent: true).controlSize(.large)
                    }
                }
            }
        } else {
            connectionTable
        }
    }

    private var connectionTable: some View {
        Table(filtered, selection: $selectedProfileID) {
            TableColumn("会话") { profile in
                Label(profile.title, systemImage: "desktopcomputer").lineLimit(1)
            }.width(min: 140, ideal: 220)
            TableColumn("地址", value: \.endpoint).width(min: 135, ideal: 180)
            TableColumn("账户", value: \.account).width(min: 95, ideal: 150)
            TableColumn("收藏") { profile in
                Button { store.favorite(profile) } label: {
                    Image(systemName: profile.favorite ? "star.fill" : "star")
                        .foregroundStyle(profile.favorite ? Color.orange : .secondary)
                }.nativeGlassButton().controlSize(.small)
                    .accessibilityLabel(profile.favorite ? "取消收藏 \(profile.title)" : "收藏 \(profile.title)")
            }.width(60)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let profile = store.profiles.first(where: { ids.contains($0.id) }) { profileActions(profile) }
            else { Button("新建会话…") { newConnection() } }
        } primaryAction: { ids in
            if let profile = store.profiles.first(where: { ids.contains($0.id) }) { connect(profile) }
        }.accessibilityIdentifier("sessions-table")
    }

    @ViewBuilder private var history: some View {
        if filteredHistory.isEmpty {
            ContentUnavailableView(search.isEmpty ? "还没有连接记录" : "没有匹配的记录", systemImage: "clock")
        } else {
            historyTable
        }
    }

    private var historyTable: some View {
        Table(filteredHistory, selection: $selectedRecordID) {
            TableColumn("会话", value: \.title).width(min: 120, ideal: 170)
            TableColumn("地址", value: \.endpoint).width(min: 135, ideal: 170)
            TableColumn("时间") { record in
                Text(record.startedAt, format: .dateTime.month().day().hour().minute())
            }.width(min: 110, ideal: 130)
            TableColumn("时长", value: \.duration).width(80)
            TableColumn("状态", value: \.outcome).width(85)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let record = store.history.first(where: { ids.contains($0.id) }),
               let profile = store.profiles.first(where: { $0.id == record.profileID }) {
                Button("再次连接") { connect(profile) }
            }
        } primaryAction: { ids in
            if let record = store.history.first(where: { ids.contains($0.id) }),
               let profile = store.profiles.first(where: { $0.id == record.profileID }) { connect(profile) }
        }
        .accessibilityIdentifier("history-table")
    }

    private var sessionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            NativeGlassControls {
                HStack(spacing: 8) {
                    ForEach(sessionWindows, id: \.session.id) { remote in
                        SessionWindowButton(session: remote.session) {
                            remote.window.deminiaturize(nil)
                            remote.window.makeKeyAndOrderFront(nil)
                        }
                    }
                }.padding(10)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text("Windows RDP")
            Spacer()
            Text("\(store.profiles.count) 个会话 · \(sessions.windows.count) 个窗口")
        }.font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder private func profileActions(_ profile: ConnectionProfile) -> some View {
        Button("连接") { connect(profile) }
        Button("编辑连接") { edit(profile) }
        Button(profile.favorite ? "取消收藏" : "收藏") { store.favorite(profile) }
        Divider()
        Button("删除连接", role: .destructive) { deleteProfile = profile }
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

private struct SessionWindowButton: View {
    @ObservedObject var session: RemoteSession
    let activate: () -> Void
    var body: some View {
        Button(action: activate) {
            Label(session.profile.title, systemImage: session.state == "connected" ? "desktopcomputer" : session.state == "connecting" ? "network" : "rectangle.slash")
        }.nativeGlassButton().help("显示会话窗口")
    }
}
