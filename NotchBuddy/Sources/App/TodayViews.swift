import SwiftUI

// Views for the Today pill: the overview card (focus timer + quick add), the
// full list, the alert card for reminders and focus blocks, and the thin
// countdown bar shown under the compact island during a block.

private let todayColor = "#2DD4BF"
private let focusColor = "#F5A524"
private let restColor  = "#34D399"

// MARK: - Overview card

struct TodayCardView: View {
    @Binding var showingDetail: Bool
    @ObservedObject private var store = TodayStore.shared
    @State private var draft = ""
    @State private var flash: String? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if showingDetail {
            TodayListView {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header
                    .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)
                FocusRow(store: store)
                    .padding(.leading, 108).padding(.trailing, 12)
                quickAdd
                    .padding(.leading, 104).padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
            .onAppear { store.syncPill() }
        }
    }

    private var summary: String {
        let open = store.openItems.count
        var parts: [String] = []
        if open > 0 { parts.append("\(open) to do") }
        if let next = store.nextReminder, let due = next.dueAt {
            parts.append("next \(TodayFormat.due(due).lowercased())")
        }
        return parts.isEmpty ? "Nothing planned" : parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: todayColor)).frame(width: 7, height: 7)
            Text("Today").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            } label: {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 2)
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 6) {
            Image(systemName: flash == nil ? "plus" : "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: flash == nil ? "#6B7079" : restColor))
                .frame(width: 12)
            ZStack(alignment: .leading) {
                if let flash, draft.isEmpty {
                    Text(flash)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: restColor))
                        .lineLimit(1)
                        .transition(.opacity)
                }
                TextField(flash == nil ? "To-do, or “in 10 min stretch”" : "", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .focused($fieldFocused)
                    .onSubmit(submit)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            // The panel is non-activating: it only takes the keyboard when asked.
            NotificationCenter.default.post(name: .islandWantsKey, object: nil)
            fieldFocused = true
        })
    }

    private func submit() {
        guard let item = store.add(draft) else { return }
        draft = ""
        let when = item.dueAt.map { " · \(TodayFormat.due($0))" } ?? ""
        withAnimation(.easeOut(duration: 0.2)) { flash = "Added\(when)" }
        SoundEngine.shared.play("pop")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeIn(duration: 0.2)) { flash = nil }
        }
    }
}

// MARK: - Focus row

private struct FocusRow: View {
    @ObservedObject var store: TodayStore

    private var phaseColor: Color {
        switch store.focus.phase {
        case .focus: return Color(hex: focusColor)
        case .rest:  return Color(hex: restColor)
        case .idle:  return Color(hex: "#6B7079")
        }
    }

    private var caption: String {
        switch store.focus.phase {
        case .idle:
            let n = store.blocksToday
            return n == 0 ? "Focus" : "\(n) block\(n == 1 ? "" : "s") today"
        case .focus: return store.focus.isPaused ? "Paused" : "Focus"
        case .rest:  return store.focus.isPaused ? "Paused" : "Break"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Ticks once a second, and only while a block is actually running.
            if store.focus.phase != .idle && !store.focus.isPaused {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    clockText(store.focus.remaining(at: ctx.date))
                }
            } else if store.focus.phase != .idle {
                clockText(store.focus.remaining(at: .now)).opacity(0.6)
            } else {
                clockText(TodayStore.focusLength).foregroundColor(Color(hex: "#6B7079"))
            }

            Text(caption)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(phaseColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            switch store.focus.phase {
            case .idle:
                TodayChip("Start", icon: "play.fill", accent: focusColor) { store.startFocus() }
            case .focus, .rest:
                if store.focus.isPaused {
                    TodayChip("Resume", icon: "play.fill", accent: focusColor) { store.resume() }
                } else if store.focus.phase == .focus {
                    TodayChip("Pause", icon: "pause.fill") { store.pause() }
                } else {
                    TodayChip("Skip", icon: "forward.fill") { store.stopFocus() }
                }
                if store.focus.phase == .focus || store.focus.isPaused {
                    TodayChip(nil, icon: "stop.fill") { store.stopFocus() }
                }
            }
        }
        .frame(height: 22)
    }

    private func clockText(_ seconds: TimeInterval) -> some View {
        Text(TodayFormat.clock(seconds))
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

private struct TodayChip: View {
    let title: String?
    let icon: String
    let accent: String?
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String?, icon: String, accent: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.accent = accent; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 7.5, weight: .bold))
                if let title { Text(title).font(.system(size: 10.5, weight: .medium)) }
            }
            .padding(.horizontal, title == nil ? 6 : 9)
            .frame(height: 20)
            .foregroundColor(accent.map { Color(hex: $0) } ?? Color(hex: "#C5C8CD"))
            .background((accent.map { Color(hex: $0) } ?? Color.white).opacity(hovered ? 0.2 : 0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Full list

struct TodayListView: View {
    let onClose: () -> Void
    @ObservedObject private var store = TodayStore.shared

    private var rows: [TodayItem] {
        store.openItems + store.items.filter(\.done)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16, height: 16)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text("Today").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Spacer()
                if store.items.contains(where: \.done) {
                    Button("Clear done") { store.clearDone() }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color(hex: todayColor).opacity(0.85))
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            if rows.isEmpty {
                Text("Nothing yet. Type a to-do, or “at 9 call Ana”.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.leading, 108).padding(.trailing, 12).padding(.top, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(rows) { item in TodayRow(item: item, store: store) }
                    }
                    .padding(.bottom, 6)
                }
                .padding(.leading, 100).padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

private struct TodayRow: View {
    let item: TodayItem
    @ObservedObject var store: TodayStore
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            Button { store.toggleDone(item.id) } label: {
                ZStack {
                    Circle().stroke(Color(hex: item.done ? restColor : "#4B5563"), lineWidth: 1.2)
                    if item.done {
                        Circle().fill(Color(hex: restColor))
                        Image(systemName: "checkmark").font(.system(size: 6, weight: .heavy)).foregroundColor(.black)
                    }
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)

            Text(item.text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: item.done ? "#5F646D" : "#C5C8CD"))
                .strikethrough(item.done, color: Color(hex: "#5F646D"))
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if let due = item.dueAt, !item.done {
                Text(TodayFormat.due(due))
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: item.firedAt == nil ? "#8E939C" : "#F5A524"))
            }
            if hovered {
                Button { store.remove(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.white.opacity(hovered ? 0.04 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
    }
}

// MARK: - Alert card (reminder due, focus block over, break over)

struct TodayAlertView: View {
    @ObservedObject private var store = TodayStore.shared

    private var who: AgentTask? {
        AgentTask.integrationAgents.first { $0.id == "integration_today" }
    }

    var body: some View {
        ZStack {
            CardBackground(wash: wash)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: who, label: label)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    PrimaryButton(primary) { store.respond(.primary) }
                    SecondaryButton(secondary) { store.respond(.secondary) }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var wash: CardBackground<EmptyView>.Wash {
        switch store.currentAlert {
        case .focusDone: return .green
        case .restDone:  return .indigo
        default:         return .cyan
        }
    }

    private var label: String {
        switch store.currentAlert {
        case let .reminder(_, _, due, late):
            let time = TodayFormat.due(due)
            return late ? "missed while you were away · \(time)" : "reminder · \(time)"
        case let .focusDone(n):
            return "focus block done · \(n) today"
        case .restDone:
            return "break is over"
        case nil:
            return ""
        }
    }

    private var title: String {
        switch store.currentAlert {
        case let .reminder(_, text, _, _): return text
        case .focusDone:                   return "Nice work. Time for a short break."
        case .restDone:                    return "Ready for another focus block?"
        case nil:                          return ""
        }
    }

    private var primary: String {
        switch store.currentAlert {
        case .focusDone: return "Take 5"
        case .restDone:  return "Focus 25 min"
        default:         return "Done"
        }
    }

    private var secondary: String {
        switch store.currentAlert {
        case .focusDone: return "Later"
        case .restDone:  return "Not now"
        default:         return "Snooze 10 min"
        }
    }
}

// MARK: - Compact countdown

/// A 2 pt line along the bottom of the compact island that shrinks as the
/// focus block (amber) or break (green) runs out. Redraws once a second, and
/// only while the island is compact and a block is running.
struct FocusCompactBar: View {
    @ObservedObject private var store = TodayStore.shared
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        if store.focus.phase != .idle {
            let color = Color(hex: store.focus.phase == .focus ? focusColor : restColor)
            let track = max(0, islandW - 28)
            Group {
                if store.focus.isPaused {
                    bar(color.opacity(0.45), width: track * store.focus.fraction(at: .now))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        bar(color.opacity(0.85), width: track * store.focus.fraction(at: ctx.date))
                    }
                }
            }
            .frame(width: track, height: 2, alignment: .leading)
            .position(x: islandW / 2, y: islandH - 2)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: 2)
            .animation(.linear(duration: 1), value: width)
    }
}
