import AppKit
import Combine

@MainActor
final class ConnectionStore: ObservableObject {
    @Published var profiles: [ConnectionProfile] = []
    @Published var history: [SessionRecord] = []
    @Published var message: String?
    let directory: URL
    private var writeBlocked = false
    private var stateURL: URL { directory.appendingPathComponent("connections.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Gravix", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: stateURL))
                guard state.version == 1 else { throw CocoaError(.coderReadCorrupt) }
                profiles = state.profiles
                history = state.history.map { record in
                    var r = record
                    if r.endedAt == nil { r.endedAt = Date(); r.outcome = "上次运行中断" }
                    return r
                }
            }
        } catch {
            message = "无法读取会话资料：\(error.localizedDescription)"
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let backup = self.directory.appendingPathComponent("connections-backup-\(UUID().uuidString).json")
                do { try FileManager.default.moveItem(at: stateURL, to: backup) }
                catch { writeBlocked = true; message = "无法保存损坏资料的备份，暂时不要修改连接。\(error.localizedDescription)" }
            }
        }
    }
    private func persist(profiles: [ConnectionProfile], history: [SessionRecord]) throws {
        if writeBlocked { throw FormError(message: "现有资料无法安全备份，已暂停保存。") }
        let data = try JSONEncoder().encode(SavedState(profiles: profiles, history: Array(history.prefix(200))))
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }
    func save() {
        do { try persist(profiles: profiles, history: history) }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }
    func upsert(_ profile: ConnectionProfile, password: String) throws {
        if let validation = profile.validationError { throw FormError(message: validation) }
        let previousPassword = try PasswordVault.read(profile.id)
        if profile.rememberPassword { try PasswordVault.save(password, for: profile.id) }
        else { try PasswordVault.delete(profile.id) }
        var changed = profiles
        if let index = changed.firstIndex(where: { $0.id == profile.id }) { changed[index] = profile }
        else { changed.append(profile) }
        do { try persist(profiles: changed, history: history) }
        catch {
            // Preserve the old credential if the matching connection could not be saved.
            if let previousPassword { try? PasswordVault.save(previousPassword, for: profile.id) }
            else { try? PasswordVault.delete(profile.id) }
            throw error
        }
        profiles = changed
    }
    func remove(_ profile: ConnectionProfile) {
        do { try PasswordVault.delete(profile.id); profiles.removeAll { $0.id == profile.id }; save() }
        catch { message = error.localizedDescription }
    }
    func favorite(_ profile: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].favorite.toggle(); save()
    }
    func begin(_ profile: ConnectionProfile) -> UUID {
        let record = SessionRecord(profileID: profile.id, title: profile.title, endpoint: profile.endpoint)
        history.insert(record, at: 0); history = Array(history.prefix(200)); save(); return record.id
    }
    func connected(_ id: UUID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].connectedAt = Date(); history[index].outcome = "已连接"; save()
    }
    func ended(_ id: UUID, outcome: String) {
        guard let index = history.firstIndex(where: { $0.id == id }), history[index].endedAt == nil else { return }
        history[index].endedAt = Date(); history[index].outcome = outcome; save()
    }
    struct FormError: LocalizedError { let message: String; var errorDescription: String? { message } }
}
