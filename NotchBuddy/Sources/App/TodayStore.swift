import AppKit
import Combine
import Foundation

// "Today": a focus timer, quick to-dos and reminders that live in the island.
// Everything stays on this Mac (UserDefaults); nothing is sent anywhere.
// The Windows twin is windows/src/core/today.ts — keep the two in step.

// MARK: - Model

struct TodayItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    /// nil = a plain to-do with no time.
    var dueAt: Date?
    var done: Bool = false
    var doneAt: Date? = nil
    var createdAt: Date = .now
    /// Set once the reminder has been shown, so it never fires twice.
    var firedAt: Date? = nil
}

enum FocusPhase: String, Codable {
    case idle, focus, rest
}

struct FocusSession: Codable, Equatable {
    var phase: FocusPhase = .idle
    /// When the running phase ends; nil while paused or idle.
    var endsAt: Date? = nil
    /// Seconds left when paused.
    var pausedRemaining: TimeInterval? = nil
    /// Full length of the current phase, for the progress bar.
    var duration: TimeInterval = 0

    var isPaused: Bool { phase != .idle && endsAt == nil }

    func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }

    /// 1 → 0 as the phase runs out.
    func fraction(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }
}

enum TodayAlert: Equatable {
    case reminder(id: UUID, text: String, dueAt: Date, late: Bool)
    case focusDone(blocksToday: Int)
    case restDone
}

// MARK: - Quick add parser

/// Turns "in 10 min stretch", "tomorrow at 9 dentist" or "a las 17:30 gym" into a
/// title and an optional due time. A few patterns, no model: it works offline and
/// never sends what you type anywhere. Mirror of windows/src/core/quickadd.ts.
enum QuickAdd {
    struct Result: Equatable {
        var title: String
        var dueAt: Date?
        var relative: Bool
    }

    // A time written with "at"/"a las" wins over the relative form, so
    // "a las 9h" is nine o'clock, not nine hours from now.
    private static let atTime   = #"(?:^|\s)(?:at|a\s+las|a\s+la|@)\s*(\d{1,2})(?:[:.h](\d{2})|h)?\s*(am|pm)?(?=\s|$|[,.!?])"#
    private static let relative = #"(?:^|\s)(?:(?:in|en|dentro\s+de)\s+)?(\d{1,3})\s*(h|hr|hrs|hours?|horas?|m|mins?|minutes?|minutos?)(?=\s|$|[,.!?])"#
    private static let bareTime = #"(?:^|\s)(\d{1,2})(?::(\d{2})\s*(am|pm)?|\s*(am|pm))(?=\s|$|[,.!?])"#
    private static let dayWord  = #"(?:^|\s)(tomorrow|mañana|manana|today|hoy)(?=\s|$|[,.!?])"#
    private static let leadIn   = #"^(?:remind\s+me\s+(?:to\s+)?|reminder:?\s*|recu[eé]rdame\s+(?:que\s+|de\s+)?|recordatorio:?\s*|timer:?\s*|temporizador(?:\s+de)?:?\s*)"#

    private struct Hit {
        let range: Range<String.Index>
        let groups: [String?]
    }

    private static func find(_ pattern: String, in s: String) -> Hit? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let whole = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: whole), let r = Range(m.range, in: s) else { return nil }
        var groups: [String?] = []
        for i in 1..<m.numberOfRanges {
            let gr = m.range(at: i)
            groups.append(gr.location == NSNotFound ? nil : Range(gr, in: s).map { String(s[$0]) })
        }
        return Hit(range: r, groups: groups)
    }

    private static func toClock(_ h: Int, _ m: Int, _ ampm: String?) -> (Int, Int)? {
        var hour = h
        let mer = ampm?.lowercased()
        if mer == "pm" && hour < 12 { hour += 12 }
        if mer == "am" && hour == 12 { hour = 0 }
        guard hour <= 23, m <= 59 else { return nil }
        return (hour, m)
    }

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Result? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var text = " \(trimmed) "

        var due: Date? = nil
        var isRelative = false
        var clock: (Int, Int)? = nil
        var dayOffset: Int? = nil

        func cut(_ hit: Hit) { text.replaceSubrange(hit.range, with: " ") }

        if let at = find(atTime, in: text) {
            clock = toClock(Int(at.groups[0] ?? "") ?? 99, Int(at.groups[1] ?? "0") ?? 0, at.groups[2])
            if clock != nil { cut(at) }
        }

        if clock == nil, let rel = find(relative, in: text),
           let n = Int(rel.groups[0] ?? ""), n > 0, let unit = rel.groups[1]?.lowercased() {
            let hours: Set<String> = ["h", "hr", "hrs", "hour", "hours", "hora", "horas"]
            let seconds = Double(n) * (hours.contains(unit) ? 3600 : 60)
            due = now.addingTimeInterval(seconds)
            isRelative = true
            cut(rel)
        }

        if clock == nil, !isRelative, let bare = find(bareTime, in: text) {
            clock = toClock(Int(bare.groups[0] ?? "") ?? 99, Int(bare.groups[1] ?? "0") ?? 0,
                            bare.groups[2] ?? bare.groups[3])
            if clock != nil { cut(bare) }
        }

        if !isRelative, let day = find(dayWord, in: text) {
            let w = (day.groups[0] ?? "").lowercased()
            dayOffset = (w == "today" || w == "hoy") ? 0 : 1
            cut(day)
        }

        if !isRelative, clock != nil || dayOffset == 1 {
            let (hh, mm) = clock ?? (9, 0)
            let start = calendar.startOfDay(for: now)
            var d = calendar.date(bySettingHour: hh, minute: mm, second: 0, of: start) ?? start
            if let off = dayOffset, off > 0 {
                d = calendar.date(byAdding: .day, value: off, to: d) ?? d
            } else if dayOffset == nil, d <= now {
                // "at 9" when nine has already gone means tomorrow morning.
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            due = d
        }

        var title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let lead = find(leadIn, in: title) { title.removeSubrange(lead.range) }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-–"))
        if title.isEmpty { title = isRelative ? "Timer" : "Reminder" }
        title = title.prefix(1).uppercased() + title.dropFirst()

        return Result(title: title, dueAt: due, relative: isRelative)
    }
}

// MARK: - Store

@MainActor
final class TodayStore: ObservableObject {
    static let shared = TodayStore()

    static let focusLength: TimeInterval = 25 * 60
    static let restLength:  TimeInterval = 5 * 60
    /// A phase that ended longer ago than this (Mac asleep, app closed) is
    /// closed quietly instead of popping an alert about it.
    private static let staleAfter: TimeInterval = 60 * 60
    /// A reminder shown more than this late is labelled as missed.
    private static let lateAfter: TimeInterval = 2 * 60

    @Published private(set) var items: [TodayItem] = []
    @Published private(set) var focus = FocusSession()
    @Published private(set) var blocksByDay: [String: Int] = [:]
    @Published private(set) var currentAlert: TodayAlert? = nil

    private var pendingAlerts: [TodayAlert] = []
    private var timer: Timer?
    private var retryTimer: Timer?
    private var viewSubscription: AnyCancellable?
    private var started = false

    private let itemsKey  = "today.items"
    private let focusKey  = "today.focus"
    private let blocksKey = "today.blocks"

    private init() {
        load()
    }

    /// Called once at launch: catches up on anything that came due while the app
    /// was closed, then waits for the next event with a single one-shot timer.
    func start() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // If something else takes over the screen while an alert is up (a
        // permission request), put the alert back in line; if the user simply
        // navigated away, it has been seen.
        viewSubscription = AppState.shared.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                self.viewChanged(to: newView)
            }
        check()
    }

    // MARK: Derived

    var openItems: [TodayItem] {
        items.filter { !$0.done }.sorted { a, b in
            switch (a.dueAt, b.dueAt) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.createdAt < b.createdAt
            }
        }
    }

    var nextReminder: TodayItem? {
        openItems.first { $0.dueAt != nil && $0.firedAt == nil }
    }

    var blocksToday: Int { blocksByDay[Self.dayKey(.now)] ?? 0 }

    // MARK: Items

    @discardableResult
    func add(_ raw: String) -> TodayItem? {
        guard let parsed = QuickAdd.parse(raw) else { return nil }
        let item = TodayItem(text: parsed.title, dueAt: parsed.dueAt)
        items.append(item)
        commit()
        return item
    }

    func toggleDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done.toggle()
        items[i].doneAt = items[i].done ? .now : nil
        commit()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        commit()
    }

    func clearDone() {
        items.removeAll { $0.done }
        commit()
    }

    func snooze(_ id: UUID, minutes: Int = 10) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].dueAt = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        items[i].firedAt = nil
        items[i].done = false
        commit()
    }

    // MARK: Focus

    func startFocus() { begin(.focus, length: Self.focusLength) }
    func startRest()  { begin(.rest,  length: Self.restLength) }

    func pause() {
        guard focus.phase != .idle, let endsAt = focus.endsAt else { return }
        focus.pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        focus.endsAt = nil
        commit()
    }

    func resume() {
        guard focus.isPaused else { return }
        focus.endsAt = Date.now.addingTimeInterval(focus.pausedRemaining ?? 0)
        focus.pausedRemaining = nil
        commit()
    }

    func stopFocus() {
        focus = FocusSession()
        commit()
    }

    private func begin(_ phase: FocusPhase, length: TimeInterval) {
        focus = FocusSession(phase: phase, endsAt: Date.now.addingTimeInterval(length),
                             pausedRemaining: nil, duration: length)
        SoundEngine.shared.play(phase == .focus ? "work" : "yawn")
        commit()
    }

    // MARK: Alerts

    enum AlertAction { case primary, secondary }

    /// The buttons on the alert card.
    func respond(_ action: AlertAction) {
        guard let alert = currentAlert else { return }
        currentAlert = nil
        AppState.shared.isPinned = false
        switch (alert, action) {
        case let (.reminder(id, _, _, _), .primary):   markDone(id)
        case let (.reminder(id, _, _, _), .secondary): snooze(id)
        case (.focusDone, .primary):                    startRest()
        case (.restDone, .primary):                     startFocus()
        default:                                        break
        }
        // Starting a break or a block re-runs the clock, which may already have
        // put the next alert on screen.
        if currentAlert != nil { return }
        if pendingAlerts.isEmpty {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        } else {
            presentNext()
        }
    }

    private func markDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].done else { return }
        items[i].done = true
        items[i].doneAt = .now
        commit()
    }

    private func enqueue(_ alert: TodayAlert) {
        pendingAlerts.append(alert)
    }

    private func presentNext() {
        guard currentAlert == nil, !pendingAlerts.isEmpty else { return }
        let state = AppState.shared
        // A permission request, another alert or the launch greeting is on
        // screen: wait for it.
        let greeting = state.mode == .expanded && state.view == .greeting
        if state.isPinned || state.pendingApproval != nil || greeting {
            scheduleRetry()
            return
        }
        let next = pendingAlerts.removeFirst()
        currentAlert = next
        state.isPinned = true
        switch next {
        case .reminder:
            SoundEngine.shared.play("question")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.wink)
        case .focusDone:
            SoundEngine.shared.play("finish")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
        case .restDone:
            SoundEngine.shared.play("greet")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.reminder)
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.retryTimer = nil
                self?.presentNext()
            }
        }
    }

    private func viewChanged(to newView: IslandView) {
        guard newView != .reminder, let alert = currentAlert else { return }
        currentAlert = nil
        if AppState.shared.pendingApproval != nil {
            // Pushed aside by a permission request: show it again afterwards.
            pendingAlerts.insert(alert, at: 0)
            scheduleRetry()
        } else {
            // The user moved on; the item stays in the list, unchecked.
            AppState.shared.isPinned = false
        }
    }

    // MARK: Clock

    /// Fires whatever is due, then arms one timer for the next event. No polling:
    /// between events the store costs nothing.
    private func check() {
        let now = Date.now
        var changed = false

        if focus.phase != .idle, let endsAt = focus.endsAt, endsAt <= now {
            let stale = now.timeIntervalSince(endsAt) > Self.staleAfter
            let finished = focus.phase
            if finished == .focus {
                let key = Self.dayKey(endsAt)
                blocksByDay[key, default: 0] += 1
            }
            focus = FocusSession()
            changed = true
            if !stale {
                enqueue(finished == .focus ? .focusDone(blocksToday: blocksToday) : .restDone)
            }
        }

        for i in items.indices {
            guard !items[i].done, items[i].firedAt == nil, let due = items[i].dueAt, due <= now else { continue }
            items[i].firedAt = now
            changed = true
            let late = now.timeIntervalSince(due) > Self.lateAfter
            enqueue(.reminder(id: items[i].id, text: items[i].text, dueAt: due, late: late))
        }

        if changed { save() }
        syncPill()
        arm()
        presentNext()
    }

    private func arm() {
        timer?.invalidate()
        timer = nil
        let candidates = [focus.endsAt, nextReminder?.dueAt].compactMap { $0 }
        guard let next = candidates.min() else { return }
        let t = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Every mutation goes through here: persist, re-arm, refresh the pill.
    private func commit() {
        save()
        check()
    }

    /// The Today pill's mini Mochi works during a focus block and naps on a break.
    func syncPill() {
        let s: BotState
        switch focus.phase {
        case .focus: s = focus.isPaused ? .idle : .working
        case .rest:  s = .sleeping
        case .idle:  s = .idle
        }
        if AppState.shared.tasks.first(where: { $0.id == "integration_today" })?.state != s {
            AppState.shared.updateTask(id: "integration_today", state: s)
        }
    }

    // MARK: Persistence

    private func load() {
        let ud = UserDefaults.standard
        let dec = JSONDecoder()
        if let d = ud.data(forKey: itemsKey), let v = try? dec.decode([TodayItem].self, from: d) { items = v }
        if let d = ud.data(forKey: focusKey), let v = try? dec.decode(FocusSession.self, from: d) { focus = v }
        if let d = ud.data(forKey: blocksKey), let v = try? dec.decode([String: Int].self, from: d) { blocksByDay = v }

        // Ticked items go away the day after; block counts are kept for two weeks.
        let today = Calendar.current.startOfDay(for: .now)
        items.removeAll { $0.done && ($0.doneAt ?? $0.createdAt) < today }
        let oldest = Self.dayKey(Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today)
        blocksByDay = blocksByDay.filter { $0.key >= oldest }
    }

    private func save() {
        let ud = UserDefaults.standard
        let enc = JSONEncoder()
        if let d = try? enc.encode(items)       { ud.set(d, forKey: itemsKey) }
        if let d = try? enc.encode(focus)       { ud.set(d, forKey: focusKey) }
        if let d = try? enc.encode(blocksByDay) { ud.set(d, forKey: blocksKey) }
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Formatting

enum TodayFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "14:30", "Tomorrow 09:00", "Thu 09:00".
    static func due(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

extension Notification.Name {
    /// A text field outside the chat needs the panel to become key.
    static let islandWantsKey = Notification.Name("notchBuddy.islandWantsKey")
}
