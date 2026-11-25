import CryptoKit
import Foundation

// MARK: - Wire format (docs/REMOTE.md)
// Mirrors windows/src-tauri/src/remote.rs `mod wire`. Test vectors shared by both
// sides live in Tests/RemoteProtocolTests.swift.

enum RemoteCrypto {
    static let magic = Data("VDR1".utf8)
    static let info = Data("voltadock-remote/1".utf8)
    static let maxFrame = (1 << 20) + 16

    /// (iPad → desktop, desktop → iPad).
    static func derive(key: Data, clientRandom: Data, serverRandom: Data) -> (FrameCipher, FrameCipher) {
        let okm = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: key),
            salt: clientRandom + serverRandom,
            info: info,
            outputByteCount: 64
        )
        let bytes = okm.withUnsafeBytes { Data($0) }
        return (FrameCipher(key: Data(bytes.prefix(32))), FrameCipher(key: Data(bytes.suffix(32))))
    }

    static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        let ok = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(ok == errSecSuccess, "no randomness")
        return data
    }
}

enum RemoteError: Error, Equatable {
    case badFrame
    case badKey
    case closed
    case timeout
    case notVoltaDock
}

/// One direction of an encrypted stream: ChaCha20-Poly1305, nonce = 4 zero
/// bytes + big-endian counter.
struct FrameCipher: Sendable {
    private let keyData: Data
    private(set) var counter: UInt64 = 0

    init(key: Data) { self.keyData = key }

    private var key: SymmetricKey { SymmetricKey(data: keyData) }

    private mutating func nextNonce() throws -> ChaChaPoly.Nonce {
        var n = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { n.append(contentsOf: $0) }
        counter += 1
        return try ChaChaPoly.Nonce(data: n)
    }

    /// ciphertext ‖ tag
    mutating func seal(_ plain: Data) throws -> Data {
        let box = try ChaChaPoly.seal(plain, using: key, nonce: nextNonce())
        return box.ciphertext + box.tag
    }

    mutating func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 16 else { throw RemoteError.badFrame }
        let nonce = try nextNonce()
        let bytes = Data(sealed)
        let box = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: Data(bytes.prefix(bytes.count - 16)),
            tag: Data(bytes.suffix(16))
        )
        do { return try ChaChaPoly.open(box, using: key) } catch { throw RemoteError.badKey }
    }

    /// u32 big-endian length ‖ sealed
    mutating func frame(_ plain: Data) throws -> Data {
        let sealed = try seal(plain)
        var out = Data()
        withUnsafeBytes(of: UInt32(sealed.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(sealed)
        return out
    }
}

// MARK: - JSON

/// Just enough JSON to carry `tool_input` around and show it.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
}

// MARK: - Messages

/// A Claude Code hook payload, trimmed by the desktop app.
struct HookEvent: Codable, Sendable, Equatable {
    var hook_event_name: String?
    var session_id: String?
    var cwd: String?
    var request_id: String?
    var tool_name: String?
    var tool_input: [String: JSONValue]?
    var prompt: String?
    var message: String?
    var last_assistant_message: String?
    var notification_type: String?
    var error: String?
    var error_details: String?
}

struct RecentSession: Codable, Sendable, Equatable {
    var id: String
    var cwd: String
    var status: String
    var detail: String
    var lastSeen: Double
}

/// Everything the desktop app may send; `type` says which fields are set.
struct Incoming: Decodable, Sendable {
    var type: String
    var host: String?
    var version: String?
    var pending: [HookEvent]?
    var sessions: [RecentSession]?
    var event: HookEvent?
    var request_id: String?
    var decision: String?
}

struct Outgoing: Encodable, Sendable {
    var type: String
    var device: String? = nil
    var version: String? = nil
    var request_id: String? = nil
    var decision: String? = nil

    static func hello(device: String, version: String) -> Outgoing {
        Outgoing(type: "hello", device: device, version: version)
    }
    static func ack(_ id: String) -> Outgoing { Outgoing(type: "ack", request_id: id) }
    static func decision(_ id: String, allow: Bool) -> Outgoing {
        Outgoing(type: "decision", request_id: id, decision: allow ? "allow" : "deny")
    }
    static let refresh = Outgoing(type: "refresh")
    static let ping = Outgoing(type: "ping")
}
