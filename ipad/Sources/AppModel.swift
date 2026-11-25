import Foundation
import Observation
import UIKit

// MARK: - What the screen shows

struct Approval: Identifiable, Equatable, Sendable {
    let id: String          // request_id
    let sessionId: String
    let project: String
    let tool: String
    /// What Allow actually authorises: the command, the file, the URL…
    let target: String
    let receivedAt: Date
    var sending = false
}

struct SessionRow: Identifiable, Equatable, Sendable {
    let id: String
    var project: String
    var cwd: String
    /// working, waiting, finished, limit, ended
    var status: String
    var detail: String
    var lastSeen: Date
}

struct ActivityItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let at: Date
    let project: String
    let text: String
    let symbol: String
}

enum LinkState: Equatable {
    case unpaired
    case connecting(String)
    case connected(String)
    case offline(String)
}

// MARK: - Model

@MainActor
@Observable
final class AppModel {
    private(set) var pairing: PairingInfo?
    private(set) var link: LinkState = .unpaired
    private(set) var approvals: [Approval] = []
    private(set) var sessions: [SessionRow] = []
    private(set) var activity: [ActivityItem] = []
    private(set) var lastFinished: Date?
    private(set) var today: TodaySnapshot?
    /// Desktop clock minus this iPad's clock, in seconds, when `today` arrived.
    private(set) var clockOffset: TimeInterval = 0
    var pairingError: String?

    /// Fake data for screenshots and previews (launch argument `-demo`).
    let demo: Bool

    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var sender: RemoteSender?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var isActive = true

    /// The relay gives up on a request 110 s after it arrived.
    nonisolated static let approvalLifetime: TimeInterval = 105

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("-demo")) {
        self.demo = demo
        if demo {
            loadDemo()
        } else {
            pairing = PairingStore.load()
            link = pairing == nil ? .unpaired : .offline("")
        }
        expiry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.dropExpired()
            }
        }
    }

    // MARK: Pairing

    func pair(with text: String) {
        guard let info = PairingCode.parse(text) else {
            pairingError = "Ese código no es de VoltaDock. Abre Ajustes → iPad en tu ordenador y vuelve a escanearlo."
            return
        }
        pairingError = nil
        PairingStore.save(info)
        pairing = info
        restart()
    }

    func forget() {
        stop()
        PairingStore.clear()
        pairing = nil
        approvals = []
        sessions = []
        activity = []
        today = nil
        TodayNotifications.clear()
        link = .unpaired
    }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        isActive = active
        guard !demo else { return }
        if active {
            if case .connected = link {
                // Requests that arrived while in the background are now on screen.
                for a in approvals { send(.ack(a.id)) }
            } else {
                restart()
            }
        }
    }

    func restart() {
        guard !demo, pairing != nil else { return }
        stop()
        runner = Task { [weak self] in await self?.run() }
    }

    private func stop() {
        runner?.cancel()
        runner = nil
        sender = nil
    }

    func refresh() { send(.refresh) }

    private func send(_ message: Outgoing) {
        guard let sender else { return }
        Task {
            do { try await sender.send(message) } catch { /* the reader notices and reconnects */ }
        }
    }

    // MARK: Connection loop

    private func run() async {
        var delay: UInt64 = 1
        while !Task.isCancelled, let pairing {
            var lastError = ""
            for host in pairing.hosts {
                if Task.isCancelled { return }
                link = .connecting(pairing.name)
                do {
                    let (sender, reader) = try await RemoteHandshake.open(
                        host: host, pairing: pairing,
                        device: UIDevice.current.name, version: Self.appVersion
                    )
                    self.sender = sender
                    delay = 1
                    let welcomed = await read(reader, sender: sender, hostName: pairing.name)
                    self.sender = nil
                    // The desktop closes the connection without a word when the
                    // key is wrong, so no welcome at all means "not paired any more".
                    lastError = welcomed
                        ? "Se perdió la conexión"
                        : "\(pairing.name) no aceptó este iPad. Si pulsaste Olvidar iPads, vuelve a emparejarlo."
                    break
                } catch {
                    lastError = "No encuentro \(pairing.name) en esta red"
                }
            }
            if Task.isCancelled { return }
            link = .offline(lastError)
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(delay * 2, 15)
        }
    }

    /// Returns whether the desktop ever said welcome.
    private func read(_ reader: RemoteReader, sender: RemoteSender, hostName: String) async -> Bool {
        var reader = reader
        let link = reader.link
        let lastSeen = Clock()
        let pinger = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                try? await sender.send(.ping)
                // The desktop pings every 25 s; 70 s of silence means it is gone.
                if lastSeen.age > 70 { link.cancel() }
            }
        }
        defer {
            pinger.cancel()
            link.cancel()
        }
        var welcomed = false
        while !Task.isCancelled {
            guard let msg = try? await reader.next() else { return welcomed }
            lastSeen.touch()
            if msg.type == "welcome" { welcomed = true }
            handle(msg, hostName: hostName)
        }
        return welcomed
    }

    // MARK: Messages

    private func handle(_ msg: Incoming, hostName: String) {
        switch msg.type {
        case "welcome":
            link = .connected(msg.host ?? hostName)
            approvals = []
            for event in msg.pending ?? [] { addApproval(event) }
            if let s = msg.sessions { merge(s) }
            if let t = msg.today { setToday(t) }
        case "today":
            if let t = msg.state { setToday(t) }
        case "sessions":
            if let s = msg.sessions { merge(s) }
        case "hook":
            if let e = msg.event { apply(e) }
        case "resolved":
            if let id = msg.request_id { approvals.removeAll { $0.id == id } }
        default:
            break
        }
    }

    // MARK: Hoy

    private func setToday(_ t: TodaySnapshot) {
        today = t
        clockOffset = t.now / 1000 - Date().timeIntervalSince1970
        TodayNotifications.schedule(t, offset: clockOffset)
    }

    /// Focus time left, on this iPad's clock.
    func focusRemaining(at date: Date = .now) -> TimeInterval {
        guard let f = today?.focus, f.phase != "idle" else { return 0 }
        if let end = f.endsAt { return max(0, end / 1000 - clockOffset - date.timeIntervalSince1970) }
        return max(0, (f.pausedRemaining ?? 0) / 1000)
    }

    func startFocus() { sendToday("focus_start") }
    func pauseFocus() { sendToday("focus_pause") }
    func resumeFocus() { sendToday("focus_resume") }
    func stopFocus() { sendToday("focus_stop") }
    func startRest() { sendToday("rest_start") }
    func toggle(_ item: TodayItemDTO) { sendToday("toggle", id: item.id) }
    func remove(_ item: TodayItemDTO) { sendToday("remove", id: item.id) }
    func addToday(_ text: String, goal: Bool) { sendToday("add", text: text, goal: goal) }

    private func sendToday(_ action: String, id: String? = nil, text: String? = nil, goal: Bool? = nil) {
        if demo { applyDemo(action, id: id, text: text, goal: goal); return }
        send(.today(action, id: id, text: text, goal: goal))
    }

    private func applyDemo(_ action: String, id: String?, text: String?, goal: Bool?) {
        guard var t = today else { return }
        let now = Date().timeIntervalSince1970 * 1000
        switch action {
        case "focus_start": t.focus = FocusDTO(phase: "focus", endsAt: now + 25 * 60_000, pausedRemaining: nil, duration: 25 * 60_000)
        case "rest_start": t.focus = FocusDTO(phase: "rest", endsAt: now + 5 * 60_000, pausedRemaining: nil, duration: 5 * 60_000)
        case "focus_pause":
            t.focus.pausedRemaining = max(0, (t.focus.endsAt ?? now) - now); t.focus.endsAt = nil
        case "focus_resume":
            t.focus.endsAt = now + (t.focus.pausedRemaining ?? 0); t.focus.pausedRemaining = nil
        case "focus_stop": t.focus = FocusDTO(phase: "idle", endsAt: nil, pausedRemaining: nil, duration: 0)
        case "toggle": if let i = t.items.firstIndex(where: { $0.id == id }) { t.items[i].done.toggle() }
        case "remove": t.items.removeAll { $0.id == id }
        case "add":
            if let text, !text.isEmpty {
                t.items.append(TodayItemDTO(id: UUID().uuidString, text: text, dueAt: nil, done: false, goal: goal ?? false, fired: false))
            }
        default: break
        }
        today = t
    }

    private func merge(_ found: [RecentSession]) {
        for s in found {
            let seen = Date(timeIntervalSince1970: s.lastSeen / 1000)
            if let i = sessions.firstIndex(where: { $0.id == s.id }) {
                if seen > sessions[i].lastSeen {
                    sessions[i].lastSeen = seen
                    if !s.detail.isEmpty { sessions[i].detail = s.detail }
                }
            } else {
                sessions.append(SessionRow(id: s.id, project: Self.project(s.cwd), cwd: s.cwd,
                                           status: s.status, detail: s.detail, lastSeen: seen))
            }
        }
        sortSessions()
    }

    private func sortSessions() {
        sessions.sort { $0.lastSeen > $1.lastSeen }
        if sessions.count > 12 { sessions.removeLast(sessions.count - 12) }
    }

    private func apply(_ e: HookEvent) {
        let name = e.hook_event_name ?? ""
        let project = Self.project(e.cwd ?? "")
        if let sid = e.session_id, !sid.isEmpty {
            touch(sid, event: name, e: e, project: project)
        }
        switch name {
        case "PermissionRequest":
            addApproval(e)
            log(project, "Pide permiso: \(Self.target(e))", "hand.raised.fill")
        case "UserPromptSubmit":
            log(project, Self.firstLine(e.prompt ?? e.message, 100), "text.bubble.fill")
        case "PreToolUse":
            log(project, Self.step(e), "bolt.fill")
        case "PostToolUseFailure":
            log(project, "Falló \(e.tool_name ?? "una herramienta")", "exclamationmark.triangle.fill")
        case "Notification":
            if let m = e.message, !m.isEmpty { log(project, Self.firstLine(m, 100), "bell.fill") }
        case "Stop":
            lastFinished = Date()
            let summary = Self.firstLine(e.last_assistant_message ?? e.message, 120)
            log(project, summary.isEmpty ? "Terminó" : summary, "checkmark.circle.fill")
        case "StopFailure":
            log(project, "Se detuvo: \(Self.firstLine(e.error_details ?? e.error, 80))", "xmark.octagon.fill")
        case "SessionStart":
            log(project, "Nueva sesión", "play.fill")
        default:
            break
        }
    }

    private func touch(_ id: String, event: String, e: HookEvent, project: String) {
        var row = sessions.first { $0.id == id }
            ?? SessionRow(id: id, project: project, cwd: e.cwd ?? "", status: "working", detail: "", lastSeen: Date())
        if !(e.cwd ?? "").isEmpty { row.project = project; row.cwd = e.cwd! }
        row.lastSeen = Date()
        switch event {
        case "UserPromptSubmit":
            row.status = "working"
            let p = Self.firstLine(e.prompt ?? e.message, 80)
            if !p.isEmpty { row.detail = p }
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "SessionStart":
            row.status = "working"
        case "PermissionRequest":
            row.status = "waiting"
        case "Notification":
            if (e.message ?? "").hasSuffix("?") || e.notification_type == "elicitation_dialog" { row.status = "waiting" }
        case "Stop":
            row.status = "finished"
            let s = Self.firstLine(e.last_assistant_message ?? e.message, 80)
            if !s.isEmpty { row.detail = s }
        case "StopFailure":
            row.status = e.error == "rate_limit" ? "limit" : "finished"
        case "SessionEnd":
            row.status = "ended"
        default:
            break
        }
        sessions.removeAll { $0.id == id }
        sessions.append(row)
        sortSessions()
    }

    private func addApproval(_ e: HookEvent) {
        guard let id = e.request_id, !id.isEmpty, !approvals.contains(where: { $0.id == id }) else { return }
        approvals.append(Approval(
            id: id,
            sessionId: e.session_id ?? "",
            project: Self.project(e.cwd ?? ""),
            tool: e.tool_name ?? "Herramienta",
            target: Self.target(e),
            receivedAt: Date()
        ))
        // Only "on screen" when the app is in front; otherwise the desktop
        // keeps its short window and the terminal takes over as usual.
        if isActive { send(.ack(id)) }
    }

    private func log(_ project: String, _ text: String, _ symbol: String) {
        guard !text.isEmpty else { return }
        activity.insert(ActivityItem(at: Date(), project: project, text: text, symbol: symbol), at: 0)
        if activity.count > 60 { activity.removeLast(activity.count - 60) }
    }

    private func dropExpired() {
        let now = Date()
        let kept = approvals.filter { now.timeIntervalSince($0.receivedAt) < Self.approvalLifetime }
        if kept.count != approvals.count { approvals = kept }
    }

    // MARK: Answering — only ever from a tap

    func decide(_ approval: Approval, allow: Bool) {
        guard let i = approvals.firstIndex(where: { $0.id == approval.id }), !approvals[i].sending else { return }
        if demo {
            approvals.remove(at: i)
            return
        }
        approvals[i].sending = true
        send(.decision(approval.id, allow: allow))
        // The desktop answers with `resolved`; if it never does, the card goes anyway.
        let id = approval.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.approvals.removeAll { $0.id == id && $0.sending }
        }
    }

    // MARK: Mood for Volt

    var mood: VoltMood {
        switch link {
        case .unpaired, .offline: return .sleeping
        case .connecting: return .thinking
        case .connected: break
        }
        if !approvals.isEmpty { return .approval }
        if let f = lastFinished, Date().timeIntervalSince(f) < 6 { return .finished }
        if sessions.contains(where: { $0.status == "working" && Date().timeIntervalSince($0.lastSeen) < 60 }) {
            return .working
        }
        return .idle
    }

    // MARK: Text helpers (same rules as the island)

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    nonisolated static func project(_ cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        return last.isEmpty ? "Sesión" : last
    }

    nonisolated static func firstLine(_ text: String?, _ max: Int) -> String {
        let line = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(line.prefix(max))
    }

    nonisolated private static let targetFields = ["command", "file_path", "path", "url", "query", "pattern", "prompt"]

    /// What Allow authorises: approving "Write" says nothing, `Write · C:\…\.env` says everything.
    nonisolated static func target(_ e: HookEvent) -> String {
        let tool = e.tool_name ?? "Herramienta"
        for f in targetFields {
            if let v = e.tool_input?[f]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                return v
            }
        }
        return tool
    }

    nonisolated private static let labels: [String: String] = [
        "Bash": "Ejecuta", "PowerShell": "Ejecuta", "Read": "Lee", "Write": "Escribe", "Edit": "Edita",
        "MultiEdit": "Edita", "Glob": "Busca", "Grep": "Busca", "WebSearch": "Búsqueda web",
        "WebFetch": "Descarga", "TodoWrite": "Tareas", "Task": "Agente", "LS": "Lista",
    ]

    nonisolated static func step(_ e: HookEvent) -> String {
        let tool = e.tool_name ?? "Herramienta"
        let label = labels[tool] ?? tool
        let t = target(e)
        return t == tool ? label : "\(label) · \(firstLine(t, 60))"
    }

    // MARK: Demo

    private func loadDemo() {
        let now = Date()
        pairing = PairingInfo(name: "DIEGO-PC", hosts: ["192.168.1.20"], port: 47821, key: Data(count: 32))
        link = .connected("DIEGO-PC")
        approvals = [
            Approval(id: "demo-1", sessionId: "s1", project: "coucou", tool: "Bash",
                     target: "npm run build && npx tauri build", receivedAt: now),
        ]
        sessions = [
            SessionRow(id: "s1", project: "coucou", cwd: "C:\\dev\\coucou", status: "waiting",
                       detail: "Añade el servidor para el iPad", lastSeen: now),
            SessionRow(id: "s2", project: "volt-site", cwd: "C:\\dev\\volt-site", status: "working",
                       detail: "Revisa los textos de la portada", lastSeen: now.addingTimeInterval(-40)),
            SessionRow(id: "s3", project: "facturas", cwd: "C:\\dev\\facturas", status: "finished",
                       detail: "Listo: exporta el CSV por mes", lastSeen: now.addingTimeInterval(-3600)),
        ]
        let ms = now.timeIntervalSince1970 * 1000
        today = TodaySnapshot(
            now: ms,
            focus: FocusDTO(phase: "focus", endsAt: ms + 18 * 60_000 + 32_000, pausedRemaining: nil, duration: 25 * 60_000),
            blocksToday: 2,
            items: [
                TodayItemDTO(id: "g1", text: "Terminar el PR del iPad", dueAt: nil, done: true, goal: true, fired: false),
                TodayItemDTO(id: "g2", text: "Enviar la factura de noviembre", dueAt: nil, done: false, goal: true, fired: false),
                TodayItemDTO(id: "g3", text: "Revisar los textos de la web", dueAt: nil, done: false, goal: true, fired: false),
                TodayItemDTO(id: "r1", text: "Llamar a Ana", dueAt: ms + 3_600_000, done: false, goal: false, fired: false),
            ]
        )
        activity = [
            ActivityItem(at: now, project: "coucou", text: "Pide permiso: npm run build && npx tauri build", symbol: "hand.raised.fill"),
            ActivityItem(at: now.addingTimeInterval(-20), project: "volt-site", text: "Edita · index.html", symbol: "bolt.fill"),
            ActivityItem(at: now.addingTimeInterval(-45), project: "coucou", text: "Lee · remote.rs", symbol: "bolt.fill"),
            ActivityItem(at: now.addingTimeInterval(-3600), project: "facturas", text: "Listo: exporta el CSV por mes", symbol: "checkmark.circle.fill"),
        ]
    }
}

/// A timestamp shared between tasks.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()
    func touch() { lock.lock(); last = Date(); lock.unlock() }
    var age: TimeInterval { lock.lock(); defer { lock.unlock() }; return Date().timeIntervalSince(last) }
}
