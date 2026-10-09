import SwiftUI
import AppKit

private struct EditorDraft: Identifiable { let id = UUID(); let profile: ConnectionProfile; let isNew: Bool }

struct ContentView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var sessions: SessionManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var navigation: WorkspaceNavigation
    @State private var search = ""
    @State private var selectedProfileID: UUID?
    @State private var draft: EditorDraft?
    @State private var passwordProfile: ConnectionProfile?
    @State private var deleteProfile: ConnectionProfile?
    @State private var confirmClear = false
    @FocusState private var searchFocused: Bool

    private var accent: Color { settings.accent.color }
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
        HStack(spacing: 16) {
            sidebar.frame(width: 228).navigationSurface(radius: 20)
            VStack(spacing: 12) {
                toolbar.navigationSurface()
                if !sessionWindows.isEmpty { sessionStrip }
                Group {
                    switch navigation.section {
                    case .computers, .favorites: computers
                    case .history: history
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
                statusBar
            }
        }.padding(16).padding(.top, 12)
            .frame(minWidth: 940, minHeight: 620)
            .background { WorkspaceBackground() }
            .tint(accent)
            .sheet(item: $draft) { draft in
                ConnectionEditor(profile: draft.profile, isNew: draft.isNew) { profile, password, connect in
                    try store.upsert(profile, password: password)
                    navigation.section = .computers
                    selectedProfileID = profile.id
                    if connect { sessions.connect(profile, password: password, store: store) }
                }
            }
            .sheet(item: $passwordProfile) { profile in
                PasswordPrompt(profile: profile) { sessions.connect(profile, password: $0, store: store) }
            }
            .alert("删除这个连接？", isPresented: Binding(get: { deleteProfile != nil }, set: { if !$0 { deleteProfile = nil } })) {
                Button("取消", role: .cancel) { deleteProfile = nil }
                Button("删除", role: .destructive) { if let profile = deleteProfile { store.remove(profile) }; deleteProfile = nil }
            } message: { Text("保存的连接和钥匙串密码将被删除，历史记录会保留。") }
            .alert("清空历史会话？", isPresented: $confirmClear) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { store.history.removeAll(); store.save() }
            } message: { Text("保存的电脑和密码不受影响。") }
            .alert("Gravix", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("好") { store.message = nil }
            } message: { Text(store.message ?? "") }
            .onReceive(NotificationCenter.default.publisher(for: .newGravixConnection)) { _ in newConnection() }
            .onChange(of: navigation.section) { _, _ in search = ""; searchFocused = false }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(.system(size: 22, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 38, height: 38).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Gravix").font(.system(size: 22, weight: .semibold, design: .rounded))
            }.padding(18).padding(.top, 8)
            VStack(spacing: 4) {
                navigationRow(.computers, count: store.profiles.count)
                navigationRow(.favorites, count: store.profiles.filter(\.favorite).count)
                navigationRow(.history, count: nil)
            }.padding(.horizontal, 10)
            HStack {
                Text("已保存会话").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { newConnection() } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("新建会话").accessibilityLabel("新建会话")
            }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 3) {
                    if sortedProfiles.isEmpty {
                        Text("暂无保存的会话").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    ForEach(sortedProfiles) { profile in
                        Button {
                            navigation.section = .computers
                            selectedProfileID = profile.id
                            search = ""
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "desktopcomputer").foregroundStyle(accent).frame(width: 18)
                                Text(profile.title).lineLimit(1)
                                Spacer(minLength: 4)
                                if profile.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                            }.font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedProfileID == profile.id ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .contextMenu { profileActions(profile) }
                    }
                }.padding(.horizontal, 10)
            }
            Divider().padding(.horizontal, 16).padding(.bottom, 10)
            navigationRow(.settings, count: nil).padding(.horizontal, 10).padding(.bottom, 14)
        }
    }

    private func navigationRow(_ section: WorkspaceSection, count: Int?) -> some View {
        Button { navigation.section = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon).font(.system(size: 15)).frame(width: 22)
                Text(section.rawValue).font(.system(size: 13, weight: navigation.section == section ? .semibold : .regular))
                Spacer(minLength: 8)
                if let count { Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary) }
            }.foregroundStyle(navigation.section == section ? accent : .primary)
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(navigation.section == section ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                // The label's entire padded row must participate in hit testing, including the spacer.
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("nav-\(section.id)")
            .accessibilityValue(navigation.section == section ? "已选中" : "未选中")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { newConnection() } label: { Label("新建会话", systemImage: "plus").padding(.vertical, 3) }
                .buttonStyle(.borderedProminent)
            if navigation.section == .computers || navigation.section == .favorites {
                Button { if let selectedProfile { connect(selectedProfile) } } label: { Label("连接", systemImage: "play.fill") }
                    .disabled(selectedProfile == nil)
                Button { if let selectedProfile { edit(selectedProfile) } } label: { Image(systemName: "pencil") }
                    .disabled(selectedProfile == nil).help("编辑选中的会话").accessibilityLabel("编辑会话")
            }
            Spacer(minLength: 8)
            if navigation.section != .settings {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(navigation.section == .history ? "搜索历史" : "搜索会话", text: $search)
                        .textFieldStyle(.plain).focused($searchFocused)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("清除搜索")
                    }
                }.padding(8).frame(width: 210)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("设置", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
        }.controlSize(.regular).padding(12)
    }

    private var sessionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("会话窗口").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(sessionWindows, id: \.session.id) { remote in
                    SessionWindowButton(session: remote.session) {
                        remote.window.deminiaturize(nil)
                        remote.window.makeKeyAndOrderFront(nil)
                    }
                }
            }.padding(4)
        }
    }

    private var computers: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(navigation.section.rawValue).font(.system(size: 22, weight: .semibold))
                Text("\(filtered.count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("双击连接").font(.caption).foregroundStyle(.tertiary)
            }.padding(24)
            if filtered.isEmpty {
                if !search.isEmpty {
                    ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: navigation.section == .favorites ? "star" : "desktopcomputer")
                            .font(.system(size: 44, weight: .light)).foregroundStyle(accent)
                        Text(navigation.section == .favorites ? "还没有收藏的会话" : "连接你的第一台 Windows 电脑").font(.title3.weight(.medium))
                        if navigation.section == .favorites {
                            Text("在会话列表中点击星标，即可在这里快速访问。").font(.callout).foregroundStyle(.secondary)
                        } else {
                            Button("新建 RDP 会话") { newConnection() }.buttonStyle(.borderedProminent).controlSize(.large)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack {
                    Text("名称 / 地址").frame(maxWidth: .infinity, alignment: .leading)
                    Text("账户").frame(width: 135, alignment: .leading)
                    Text("操作").frame(width: 113, alignment: .trailing)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(.primary.opacity(0.025))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) { ForEach(filtered) { profile in connectionRow(profile).id(profile.id) } }.padding(8)
                    }.onChange(of: selectedProfileID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func connectionRow(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: 8) {
            Button { selectedProfileID = profile.id } label: {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer").foregroundStyle(accent).font(.system(size: 19))
                        .frame(width: 38, height: 38).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(profile.endpoint).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(profile.account).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 135, alignment: .leading)
                }.padding(.vertical, 12).padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).simultaneousGesture(TapGesture(count: 2).onEnded { connect(profile) })
            Button { store.favorite(profile) } label: {
                Image(systemName: profile.favorite ? "star.fill" : "star").foregroundStyle(profile.favorite ? .orange : .secondary)
                    .frame(width: 26, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).help(profile.favorite ? "取消收藏" : "收藏").accessibilityLabel(profile.favorite ? "取消收藏 \(profile.title)" : "收藏 \(profile.title)")
            Button { connect(profile) } label: { Image(systemName: "play.fill").font(.system(size: 11)).frame(width: 26, height: 28) }
                .buttonStyle(.borderless).help("连接").accessibilityLabel("连接 \(profile.title)")
            Menu { profileActions(profile) } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 24).padding(.trailing, 12).accessibilityLabel("会话操作")
        }.background(selectedProfileID == profile.id ? accent.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selectedProfileID == profile.id ? accent.opacity(0.4) : .clear))
            .contextMenu { profileActions(profile) }
    }

    @ViewBuilder private func profileActions(_ profile: ConnectionProfile) -> some View {
        Button("连接") { connect(profile) }
        Button("编辑连接") { edit(profile) }
        Button(profile.favorite ? "取消收藏" : "收藏") { store.favorite(profile) }
        Divider()
        Button("删除连接", role: .destructive) { deleteProfile = profile }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史会话").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("清空历史", role: .destructive) { confirmClear = true }.disabled(store.history.isEmpty)
            }.padding(24)
            if filteredHistory.isEmpty {
                ContentUnavailableView(search.isEmpty ? "还没有连接记录" : "没有匹配的记录", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredHistory) { record in
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer").foregroundStyle(accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(record.endpoint).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(record.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption)
                                    Text(record.duration).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(record.outcome).font(.caption).foregroundStyle(record.outcome == "连接失败" ? .orange : .secondary).frame(width: 70)
                                Button("再连接") { if let p = store.profiles.first(where: { $0.id == record.profileID }) { connect(p) } }
                                    .disabled(!store.profiles.contains { $0.id == record.profileID })
                            }.padding(14).background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(8)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "network").foregroundStyle(accent)
            Text("Windows RDP")
            Spacer()
            Text("\(store.profiles.count) 个会话")
            Text("·").foregroundStyle(.tertiary)
            Text("\(sessions.windows.count) 个窗口")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 6)
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
            HStack(spacing: 7) {
                Circle().fill(session.state == "connected" ? Color.green : session.state == "connecting" ? .orange : .secondary).frame(width: 6, height: 6)
                Text(session.profile.title).lineLimit(1)
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain).help("显示会话窗口")
    }
}
