import AppKit
import Foundation

/// "Delete my data": what VoltaDock keeps on this Mac is emptied (to-dos,
/// reminders, habits, the chat, copies of dropped files and the saved keys).
/// Preferences stay. The Windows twin is `erase_data` in windows/src-tauri/src/lib.rs.
@MainActor
enum DataEraser {
    static func eraseAll() {
        TodayStore.shared.reset()
        AppState.shared.chatHistory = []
        for key in ["today.items", "today.focus", "today.blocks", "today.habits", "update.seen"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for key in KeychainStore.allKeys { KeychainStore.shared.remove(key) }
        // The copies of dropped files (the originals are never touched).
        try? FileManager.default.removeItem(at: HookServer.supportDir.appendingPathComponent("inbox"))
    }
}
