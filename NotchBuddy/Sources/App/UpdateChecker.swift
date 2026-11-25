import AppKit
import Foundation

/// "Is there a newer release?" One GET to GitHub's public releases API, only when
/// the user turned it on (or pressed "Check now"). Nothing about the user or the
/// Mac is sent: the request carries no identifier beyond a generic client name.
/// The Windows twin is windows/src-tauri/src/updates.rs.
enum UpdateChecker {
    enum Outcome: Equatable {
        case newer(version: String, url: String)
        case current(version: String)
        case unpublished   // nothing published yet
        case failed
    }

    private static let latest = URL(string: "https://api.github.com/repos/DiegoVolta91/VoltaDock/releases/latest")!

    /// "v1.2.3" / "1.2.3-beta" → [1, 2, 3]. Missing or odd parts count as 0.
    static func parts(_ v: String) -> [Int] {
        var core = v.trimmingCharacters(in: .whitespaces)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        core = String(core.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? "")
        let nums = core.split(separator: ".").prefix(3).map { Int($0) ?? 0 }
        return nums + Array(repeating: 0, count: 3 - nums.count)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func check() async -> Outcome {
        var req = URLRequest(url: latest, timeoutInterval: 8)
        req.setValue("volta-dock-update-check", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return .failed }
        if http.statusCode == 404 { return .unpublished }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failed }
        let tag = json["tag_name"] as? String ?? ""
        if tag.isEmpty { return .unpublished }
        var page = json["html_url"] as? String ?? ""
        // Only ever hand the UI a link on GitHub itself.
        if !page.hasPrefix("https://github.com/DiegoVolta91/VoltaDock/") { page = "" }
        let remote = parts(tag), mine = parts(currentVersion)
        if remote.lexicographicallyPrecedes(mine) || remote == mine { return .current(version: currentVersion) }
        let shown = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return .newer(version: shown, url: page)
    }

    /// Once at launch, only if the user asked for it; a version is announced once.
    @MainActor
    static func launchCheck() {
        guard AppState.shared.updateCheck else { return }
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard AppState.shared.updateCheck else { return }
            guard case let .newer(version, url) = await check(), !url.isEmpty else { return }
            let ud = UserDefaults.standard
            if ud.string(forKey: "update.seen") == version { return }
            ud.set(version, forKey: "update.seen")
            TodayStore.shared.announceUpdate(version: version, url: url)
        }
    }
}
