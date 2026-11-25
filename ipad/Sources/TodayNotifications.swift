import Foundation
import UserNotifications

/// Local notifications for Hoy: a reminder coming due and the end of a focus
/// block or break. They are scheduled on the iPad itself, so they still go off
/// when the iPad is away from the home network (they are refreshed every time
/// the desktop sends a new state). No Apple developer account or push needed.
enum TodayNotifications {
    private static let prefix = "voltadock.today."

    static func schedule(_ t: TodaySnapshot, offset: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.getPendingNotificationRequests { pending in
                let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: old)
                for r in requests(for: t, offset: offset, now: Date()) { center.add(r) }
            }
        }
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    /// Pure, so it can be tested: what should be pending for this state.
    static func requests(for t: TodaySnapshot, offset: TimeInterval, now: Date) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        func make(_ id: String, _ title: String, _ body: String, at epochMs: Double) {
            let fire = epochMs / 1000 - offset
            let wait = fire - now.timeIntervalSince1970
            guard wait > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            out.append(UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger))
        }
        for item in t.items where !item.done && item.fired != true {
            if let due = item.dueAt { make("item." + item.id, "Recordatorio", item.text, at: due) }
        }
        if t.focus.phase != "idle", let end = t.focus.endsAt {
            if t.focus.phase == "focus" {
                make("focus", "Bloque de enfoque terminado", "Toca un descanso corto.", at: end)
            } else {
                make("rest", "Se acabó el descanso", "¿Otro bloque de enfoque?", at: end)
            }
        }
        // iOS keeps at most 64 pending local notifications.
        return Array(out.prefix(60))
    }
}
