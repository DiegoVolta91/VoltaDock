import SwiftUI

/// Hoy on the iPad: focus timer, goals of the day and reminders, in step with
/// the desktop app. Everything here is a command to the desktop; the iPad shows
/// whatever state comes back.
struct TodayCard: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var asGoal = false
    @FocusState private var typing: Bool

    private let focusColor = Color(red: 0.96, green: 0.65, blue: 0.14)
    private let restColor = Color(red: 0.2, green: 0.83, blue: 0.6)
    private let teal = Color(red: 0.176, green: 0.831, blue: 0.749)

    var body: some View {
        Card {
            HStack {
                Text("Hoy").font(.title2.bold())
                if let t = model.today, goalsTotal(t) > 0 {
                    Text("\(goalsDone(t))/\(goalsTotal(t)) objetivos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(teal)
                }
                Spacer()
                if let t = model.today, t.blocksToday > 0 {
                    Text("\(t.blocksToday) bloque\(t.blocksToday == 1 ? "" : "s") hoy")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            if let t = model.today {
                focusRow(t.focus)
                Divider().overlay(Theme.cardBorder)
                list(t)
                addRow
            } else {
                Text("Aún no llega nada de «Hoy». Abre VoltaDock en el ordenador y se sincroniza solo.")
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: Focus

    private func focusRow(_ f: FocusDTO) -> some View {
        HStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = f.phase == "idle" ? 25 * 60 : Int(model.focusRemaining(at: ctx.date).rounded(.up))
                Text(String(format: "%02d:%02d", left / 60, left % 60))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(f.phase == "idle" ? Theme.secondary : (f.phase == "focus" ? focusColor : restColor))
                    .opacity(f.phase != "idle" && f.endsAt == nil ? 0.55 : 1)
            }
            Text(caption(f))
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer()
            if f.phase == "idle" {
                Button { model.startFocus() } label: { Label("Empezar", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            } else {
                if f.endsAt == nil {
                    Button { model.resumeFocus() } label: { Label("Seguir", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                } else if f.phase == "focus" {
                    Button { model.pauseFocus() } label: { Label("Pausa", systemImage: "pause.fill") }
                        .buttonStyle(.bordered)
                }
                Button { model.stopFocus() } label: {
                    Image(systemName: f.phase == "rest" ? "forward.fill" : "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func caption(_ f: FocusDTO) -> String {
        switch f.phase {
        case "focus": return f.endsAt == nil ? "Enfoque en pausa" : "Enfoque"
        case "rest": return "Descanso"
        default: return "Enfoque de 25 min"
        }
    }

    // MARK: List

    private func ordered(_ t: TodaySnapshot) -> [TodayItemDTO] {
        let open = t.items.filter { !$0.done }.sorted { a, b in
            if a.goal != b.goal { return a.goal }
            switch (a.dueAt, b.dueAt) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
        return open + t.items.filter(\.done)
    }

    @ViewBuilder
    private func list(_ t: TodaySnapshot) -> some View {
        let rows = ordered(t)
        if rows.isEmpty {
            Text("Nada todavía. Escribe un objetivo o «a las 9 llamar a Ana».")
                .foregroundStyle(Theme.secondary)
        } else {
            ForEach(rows) { item in
                HStack(spacing: 12) {
                    Button { model.toggle(item) } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(item.done ? restColor : Theme.secondary)
                    }
                    .buttonStyle(.plain)
                    if item.goal && !item.done {
                        Text("Objetivo")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(teal.opacity(0.18), in: Capsule())
                            .foregroundStyle(teal)
                    }
                    Text(item.text)
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Theme.secondary : .white)
                        .lineLimit(2)
                    Spacer()
                    if let due = item.dueAt, !item.done {
                        Text(Date(timeIntervalSince1970: due / 1000 - model.clockOffset), style: .time)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(item.fired == true ? focusColor : Theme.secondary)
                    }
                    Button { model.remove(item) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Button { asGoal.toggle() } label: {
                Text("Objetivo")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(asGoal ? teal.opacity(0.22) : Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(asGoal ? teal : Theme.secondary)
            }
            .buttonStyle(.plain)
            TextField(asGoal ? "Objetivo del día" : "Tarea, o «en 10 min estirar»", text: $draft)
                .focused($typing)
                .submitLabel(.done)
                .onSubmit(submit)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
            Button("Añadir", action: submit)
                .buttonStyle(.bordered)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.addToday(text, goal: asGoal)
        draft = ""
    }

    private func goalsTotal(_ t: TodaySnapshot) -> Int { t.items.filter(\.goal).count }
    private func goalsDone(_ t: TodaySnapshot) -> Int { t.items.filter { $0.goal && $0.done }.count }
}
