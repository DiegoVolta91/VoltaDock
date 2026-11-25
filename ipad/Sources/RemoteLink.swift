import Foundation
@preconcurrency import Network

// MARK: - TCP link
// A thin async wrapper over NWConnection: connect, send, receive exactly n bytes.

final class TCPLink: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "voltadock.link")

    private init(_ connection: NWConnection) { self.connection = connection }

    static func connect(host: String, port: UInt16, timeout: TimeInterval) async throws -> TCPLink {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw RemoteError.closed }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        let params = NWParameters(tls: nil, tcp: tcp)
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let link = TCPLink(conn)
        try await link.start(timeout: timeout)
        return link
    }

    private func start(timeout: TimeInterval) async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    once.run { cont.resume() }
                case .failed(let err):
                    once.run { cont.resume(throwing: err) }
                case .waiting(let err):
                    // Unreachable host: give up now, the next address may work.
                    once.run { cont.resume(throwing: err) }
                    connection.cancel()
                case .cancelled:
                    once.run { cont.resume(throwing: RemoteError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [connection] in
                once.run {
                    cont.resume(throwing: RemoteError.timeout)
                    connection.cancel()
                }
            }
        }
    }

    /// Queues bytes on the connection right away (in call order) and reports later.
    func enqueue(_ data: Data, completion: @escaping @Sendable (Error?) -> Void) {
        connection.send(content: data, completion: .contentProcessed { err in completion(err) })
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    func receive(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, err in
                if let err { cont.resume(throwing: err); return }
                if let data, data.count == count { cont.resume(returning: data); return }
                cont.resume(throwing: isComplete ? RemoteError.closed : RemoteError.badFrame)
            }
        }
    }

    func cancel() { connection.cancel() }
}

/// Resumes a continuation at most once, whichever callback gets there first.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

// MARK: - Encrypted session

/// Sending side of a connection. Receiving is done by `RemoteReader`, owned by
/// one task, so each cipher is only ever touched from one place.
actor RemoteSender {
    private let link: TCPLink
    private var cipher: FrameCipher

    init(link: TCPLink, cipher: FrameCipher) {
        self.link = link
        self.cipher = cipher
    }

    func send(_ message: Outgoing) async throws {
        let json = try JSONEncoder().encode(message)
        let frame = try cipher.frame(json)
        // Queued synchronously, while still on the actor, so frames go out in
        // counter order even when several sends overlap.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            link.enqueue(frame) { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }
    }
}

struct RemoteReader: Sendable {
    let link: TCPLink
    var cipher: FrameCipher

    mutating func next() async throws -> Incoming {
        let header = try await link.receive(exactly: 4)
        let len = header.reduce(0) { ($0 << 8) | Int($1) }
        guard len >= 16, len <= RemoteCrypto.maxFrame else { throw RemoteError.badFrame }
        let body = try await link.receive(exactly: len)
        let plain = try cipher.open(body)
        return try JSONDecoder().decode(Incoming.self, from: plain)
    }
}

enum RemoteHandshake {
    /// Connects, swaps randoms, derives the keys and says hello.
    static func open(host: String, pairing: PairingInfo, device: String, version: String) async throws
        -> (RemoteSender, RemoteReader) {
        let link = try await TCPLink.connect(host: host, port: pairing.port, timeout: 4)
        do {
            let clientRandom = RemoteCrypto.random(32)
            try await link.send(RemoteCrypto.magic + clientRandom)
            // A receive cannot be cancelled, but closing the link ends it.
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                link.cancel()
            }
            defer { watchdog.cancel() }
            let reply = try await link.receive(exactly: 36)
            guard reply.prefix(4) == RemoteCrypto.magic else { throw RemoteError.notVoltaDock }
            let serverRandom = Data(reply.suffix(32))
            let (c2s, s2c) = RemoteCrypto.derive(key: pairing.key, clientRandom: clientRandom, serverRandom: serverRandom)
            let sender = RemoteSender(link: link, cipher: c2s)
            try await sender.send(.hello(device: device, version: version))
            return (sender, RemoteReader(link: link, cipher: s2c))
        } catch {
            link.cancel()
            throw error
        }
    }
}
