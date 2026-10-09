import Foundation

@main struct ModelTests {
    @MainActor static func main() throws {
        var p = ConnectionProfile()
        assert(p.validationError != nil)
        p.host = " 192.0.2.10 "; p.username = " test "; p.normalize()
        assert(p.validationError == nil)
        p.port = 65536; assert(p.validationError != nil); p.port = 3389
        p.host = "rdp://example.com"; assert(p.validationError != nil)
        p.host = "2001:db8::1"; assert(p.validationError == nil)
        assert(p.endpoint == "[2001:db8::1]:3389")
        p.width = 100; assert(p.validationError != nil); p.width = 1440
        p.host = "example.com"; p.name = "Test"; p.rememberPassword = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gravix-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory); try? PasswordVault.delete(p.id) }
        let store = ConnectionStore(directory: directory)
        let password = "Gravix-test-\(UUID())"
        try store.upsert(p, password: password)
        let restored = try PasswordVault.read(p.id); assert(restored == password)
        let stateURL = directory.appendingPathComponent("connections.json")
        let backupURL = directory.appendingPathComponent("backup.json")
        try FileManager.default.moveItem(at: stateURL, to: backupURL)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: false)
        do { try store.upsert(p, password: "must-roll-back"); assertionFailure("Expected save failure") } catch {}
        let afterFailure = try PasswordVault.read(p.id); assert(afterFailure == password)
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.moveItem(at: backupURL, to: stateURL)
        let raw = try String(contentsOf: directory.appendingPathComponent("connections.json"), encoding: .utf8)
        assert(!raw.contains(password))
        let record = store.begin(p); store.connected(record); store.ended(record, outcome: "已断开")
        let loaded = ConnectionStore(directory: directory)
        assert(loaded.profiles == [p]); assert(loaded.history.count == 1); assert(loaded.history[0].connectedAt != nil)
        assert(loaded.history[0].endedAt != nil)
        p.rememberPassword = false; try store.upsert(p, password: "transient")
        let removed = try PasswordVault.read(p.id); assert(removed == nil)
        store.remove(p); assert(store.profiles.isEmpty)
        print("Profile validation, persistence, history, Keychain roundtrip and password exclusion tests passed")
    }
}
