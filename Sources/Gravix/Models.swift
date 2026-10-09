import Foundation

struct ConnectionProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = 3389
    var username = ""
    var domain = ""
    var rememberPassword = true
    var hardwareAcceleration = true
    var clipboard = true
    var dynamicResolution = true
    var retina = false
    var width = 1440
    var height = 900
    var sharedFolder = ""
    var favorite = false

    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : name }
    var endpoint: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
    var account: String { domain.isEmpty ? username : "\(domain)\\\(username)" }
    var validationError: String? {
        if host.isEmpty { return "请输入 Windows 电脑的 IP 地址或主机名。" }
        if host.contains("://") || host.contains("/") || host.contains("\\") || host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) { return "地址只填写 IP 或主机名，不含协议、路径或空格；端口单独填写。" }
        if host.hasPrefix("[") || host.hasSuffix("]") { return "IPv6 地址无需方括号，端口单独填写。" }
        if !(1...65535).contains(port) { return "端口需要在 1–65535 之间。" }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入 Windows 用户名。" }
        if !(200...8192).contains(width) || !(200...8192).contains(height) { return "分辨率需要在 200–8192 像素之间。" }
        if sharedFolder.contains(",") { return "共享文件夹路径暂不支持逗号，请选择其他文件夹。" }
        if !sharedFolder.isEmpty && !FileManager.default.fileExists(atPath: sharedFolder) { return "共享文件夹已不存在，请重新选择。" }
        return nil
    }
    mutating func normalize() {
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if domain.isEmpty, let separator = username.firstIndex(of: "\\") {
            domain = String(username[..<separator])
            username = String(username[username.index(after: separator)...])
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var title: String
    var endpoint: String
    var startedAt = Date()
    var connectedAt: Date?
    var endedAt: Date?
    var outcome = "连接中"
    var duration: String {
        guard let connectedAt else { return "—" }
        let seconds = max(0, Int((endedAt ?? Date()).timeIntervalSince(connectedAt)))
        return seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

struct SavedState: Codable {
    var version = 1
    var profiles: [ConnectionProfile] = []
    var history: [SessionRecord] = []
}
