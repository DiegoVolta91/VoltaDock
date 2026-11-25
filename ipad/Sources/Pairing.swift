import Foundation
import Security

// MARK: - Pairing code
// voltadock://pair?v=1&n=<name>&p=<port>&h=<host1>,<host2>&k=<base64url key>
// Shown as a QR code by the desktop app (Settings → iPad). See docs/REMOTE.md.

struct PairingInfo: Codable, Equatable, Sendable {
    var name: String
    var hosts: [String]
    var port: UInt16
    /// 32 bytes. Whoever holds it can approve Claude Code permissions.
    var key: Data
}

enum PairingCode {
    static func parse(_ text: String) -> PairingInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme == "voltadock", comps.host == "pair" else { return nil }
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        guard q["v"] == "1",
              let keyText = q["k"], let key = base64URLDecode(keyText), key.count == 32,
              let hostsText = q["h"], let portText = q["p"], let port = UInt16(portText), port > 0
        else { return nil }
        let hosts = hostsText.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !hosts.isEmpty else { return nil }
        let name = (q["n"]?.isEmpty == false ? q["n"]! : "PC")
        return PairingInfo(name: name, hosts: hosts, port: port, key: key)
    }

    static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}

// MARK: - Keychain
// The pairing (with its key) lives only in the Keychain, on this device only.

enum PairingStore {
    private static let service = "io.github.diegovolta91.VoltaDock.iPad"
    private static let account = "pairing"

    static func load() -> PairingInfo? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(PairingInfo.self, from: data)
    }

    @discardableResult
    static func save(_ info: PairingInfo) -> Bool {
        guard let data = try? JSONEncoder().encode(info) else { return false }
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
