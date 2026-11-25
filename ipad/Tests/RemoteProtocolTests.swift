import XCTest
@testable import VoltaDock

/// Vectors produced by windows/src-tauri/src/remote.rs (`mod wire`) and checked
/// against Python's `cryptography`: key = 00…1f, client random = 40…5f,
/// server random = 80…9f.
final class RemoteProtocolTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0) })
    private let clientRandom = Data((0..<32).map { UInt8(0x40 + $0) })
    private let serverRandom = Data((0..<32).map { UInt8(0x80 + $0) })

    private func hex(_ s: String) -> Data {
        var out = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    func testMatchesDesktopVectors() throws {
        var (c2s, s2c) = RemoteCrypto.derive(key: key, clientRandom: clientRandom, serverRandom: serverRandom)
        XCTAssertEqual(try c2s.seal(Data(#"{"type":"hello","device":"iPad"}"#.utf8)),
                       hex("6168a82a87f32dabe92b5a8963d113d9e5ae501c0a5ca0d09827e92923bc18200486646920add8a15665de950db31670"))
        XCTAssertEqual(try c2s.seal(Data(#"{"type":"ping"}"#.utf8)),
                       hex("ca722cd3117f14105665ecc904145001776d22ef4e5b59d62273250e618f29"))
        XCTAssertEqual(try s2c.open(hex("9d67e4fcc3cd3405733d865b94ddfdaca0fe0252aa71c8accf8d24744068f1044c19")),
                       Data(#"{"type":"welcome"}"#.utf8))
        XCTAssertEqual(try s2c.open(hex("ade7c2132b0ce9a5e7eef37d34bc87206f781b9b17b734f984fcb714ef08f9")),
                       Data(#"{"type":"ping"}"#.utf8))
    }

    func testWrongKeyFails() {
        var (_, s2c) = RemoteCrypto.derive(key: Data(count: 32), clientRandom: clientRandom, serverRandom: serverRandom)
        XCTAssertThrowsError(try s2c.open(hex("9d67e4fcc3cd3405733d865b94ddfdaca0fe0252aa71c8accf8d24744068f1044c19")))
    }

    func testReplayedFrameFails() throws {
        var (_, s2c) = RemoteCrypto.derive(key: key, clientRandom: clientRandom, serverRandom: serverRandom)
        let first = hex("9d67e4fcc3cd3405733d865b94ddfdaca0fe0252aa71c8accf8d24744068f1044c19")
        _ = try s2c.open(first)
        XCTAssertThrowsError(try s2c.open(first), "a frame is only valid at its own counter")
    }

    func testParsesPairingCode() throws {
        let code = "voltadock://pair?v=1&n=DIEGO-PC&p=47821&h=192.168.1.20,diego-pc.local&k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
        let info = try XCTUnwrap(PairingCode.parse(code))
        XCTAssertEqual(info.name, "DIEGO-PC")
        XCTAssertEqual(info.port, 47821)
        XCTAssertEqual(info.hosts, ["192.168.1.20", "diego-pc.local"])
        XCTAssertEqual(info.key, key)
    }

    func testRejectsOtherCodes() {
        XCTAssertNil(PairingCode.parse("https://example.com"))
        XCTAssertNil(PairingCode.parse("voltadock://pair?v=1&n=x&p=1&h=a&k=short"))
        XCTAssertNil(PairingCode.parse("voltadock://pair?v=2&n=x&p=47821&h=a&k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"))
    }

    func testDecodesHookEvent() throws {
        let json = #"{"type":"hook","event":{"hook_event_name":"PermissionRequest","request_id":"9-1","cwd":"C:\\dev\\coucou","tool_name":"Bash","tool_input":{"command":"npm test","timeout":120}}}"#
        let msg = try JSONDecoder().decode(Incoming.self, from: Data(json.utf8))
        let e = try XCTUnwrap(msg.event)
        XCTAssertEqual(AppModel.target(e), "npm test")
        XCTAssertEqual(AppModel.project(e.cwd ?? ""), "coucou")
    }
}

/// Talks to ci/mock_desktop.py, a stand-in for the Windows app written from
/// docs/REMOTE.md. Runs only when CI starts the mock (TEST_RUNNER_VOLTADOCK_E2E=1).
final class RemoteEndToEndTests: XCTestCase {
    func testHandshakeApproveAndResolve() async throws {
        guard ProcessInfo.processInfo.environment["VOLTADOCK_E2E"] == "1" else {
            throw XCTSkip("mock desktop not running")
        }
        let pairing = PairingInfo(name: "mock", hosts: ["127.0.0.1"], port: 47821,
                                  key: Data((0..<32).map { UInt8($0) }))
        let (sender, start) = try await RemoteHandshake.open(host: "127.0.0.1", pairing: pairing,
                                                             device: "test", version: "0")
        var reader = start
        let welcome = try await reader.next()
        XCTAssertEqual(welcome.type, "welcome")
        let pending = try XCTUnwrap(welcome.pending?.first)
        XCTAssertEqual(pending.tool_name, "Bash")
        let id = try XCTUnwrap(pending.request_id)

        try await sender.send(.ack(id))
        try await sender.send(.decision(id, allow: true))
        let resolved = try await reader.next()
        XCTAssertEqual(resolved.type, "resolved")
        XCTAssertEqual(resolved.request_id, id)
        XCTAssertEqual(resolved.decision, "allow")
    }

    // MARK: Hoy

    func testDecodesTodayInWelcomeAndUpdates() throws {
        let json = #"""
        {"type":"welcome","host":"PC","today":{"now":1000000,"blocksToday":2,
         "focus":{"phase":"focus","endsAt":1900000,"pausedRemaining":null,"duration":1500000},
         "items":[{"id":"a","text":"Objetivo","dueAt":null,"done":false,"goal":true,"fired":false}]}}
        """#
        let msg = try JSONDecoder().decode(Incoming.self, from: Data(json.utf8))
        XCTAssertEqual(msg.today?.focus.phase, "focus")
        XCTAssertEqual(msg.today?.items.first?.goal, true)
        let none = try JSONDecoder().decode(Incoming.self, from: Data(#"{"type":"welcome","today":null}"#.utf8))
        XCTAssertNil(none.today)
    }

    func testTodayCommandEncoding() throws {
        let data = try JSONEncoder().encode(Outgoing.today("add", text: "x", goal: true))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["type"] as? String, "today_cmd")
        XCTAssertEqual(obj?["action"] as? String, "add")
        XCTAssertEqual(obj?["goal"] as? Bool, true)
    }

    func testNotificationsOnlyForFutureOpenReminders() {
        let now = Date()
        let ms = now.timeIntervalSince1970 * 1000
        let t = TodaySnapshot(
            now: ms,
            focus: FocusDTO(phase: "focus", endsAt: ms + 600_000, pausedRemaining: nil, duration: 1_500_000),
            blocksToday: 0,
            items: [
                TodayItemDTO(id: "future", text: "a", dueAt: ms + 3_600_000, done: false, goal: false, fired: false),
                TodayItemDTO(id: "past", text: "b", dueAt: ms - 60_000, done: false, goal: false, fired: false),
                TodayItemDTO(id: "done", text: "c", dueAt: ms + 3_600_000, done: true, goal: false, fired: false),
            ]
        )
        let ids = Set(TodayNotifications.requests(for: t, offset: 0, now: now).map(\.identifier))
        XCTAssertEqual(ids, ["voltadock.today.item.future", "voltadock.today.focus"])
    }
}
