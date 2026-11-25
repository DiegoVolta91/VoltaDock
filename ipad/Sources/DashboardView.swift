import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmForget = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if geo.size.width > 900 {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 20) { approvalsCard; sessionsCard }
                                .frame(maxWidth: .infinity)
                            activityCard
                                .frame(width: min(420, geo.size.width * 0.38))
                        }
                    } else {
                        approvalsCard
                        sessionsCard
                        activityCard
                    }
                }
                .padding(24)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .refreshable { model.refresh() }
        }
        .confirmationDialog("¿Olvidar este ordenador?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Olvidar", role: .destructive) { model.forget() }
        } message: {
            Text("Tendrás que volver a escanear el código para conectarte.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VoltView(mood: model.mood, size: 120)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("VoltaDock")
                    .font(.largeTitle.bold())
                HStack(spacing: 8) {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.title3)
                        .foregroundStyle(Theme.secondary)
                }
                if case .offline(let why) = model.link, !why.isEmpty {
                    Text(why)
                        .font(.callout)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer()
            Menu {
                Button { model.refresh() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                Button { model.restart() } label: { Label("Reconectar", systemImage: "antenna.radiowaves.left.and.right") }
                Divider()
                Button(role: .destructive) { confirmForget = true } label: {
                    Label("Olvidar este ordenador", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private var statusText: String {
        switch model.link {
        case .unpaired: return "Sin emparejar"
        case .connecting(let name): return "Buscando \(name)…"
        case .connected(let name): return "Conectado a \(name)"
        case .offline: return "Sin conexión"
        }
    }

    private var statusColor: Color {
        switch model.link {
        case .connected: return Theme.allow
        case .connecting: return Theme.amber
        default: return Theme.deny
        }
    }

    // MARK: Approvals

    private var approvalsCard: some View {
        Card {
            sectionTitle("Permisos", count: model.approvals.count)
            if model.approvals.isEmpty {
                Text("Nada que aprobar. Cuando Claude Code pida permiso, aparecerá aquí.")
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(model.approvals) { approval in
                    ApprovalRow(approval: approval)
                    if approval.id != model.approvals.last?.id { Divider().overlay(Theme.cardBorder) }
                }
            }
        }
    }

    // MARK: Sessions

    private var sessionsCard: some View {
        Card {
            sectionTitle("Conversaciones", count: nil)
            if model.sessions.isEmpty {
                Text("Todavía no hay conversaciones recientes.")
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(model.sessions) { s in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(color(for: s.status)).frame(width: 10, height: 10).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.project).font(.headline)
                                Text(label(for: s.status))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(color(for: s.status).opacity(0.18), in: Capsule())
                                    .foregroundStyle(color(for: s.status))
                                Spacer()
                                Text(s.lastSeen, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                            if !s.detail.isEmpty {
                                Text(s.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    private func label(for status: String) -> String {
        switch status {
        case "working": return "Trabajando"
        case "waiting": return "Te espera"
        case "finished": return "Terminada"
        case "limit": return "Límite"
        case "ended": return "Cerrada"
        default: return status
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "working": return VoltMood.working.color
        case "waiting": return VoltMood.approval.color
        case "finished": return VoltMood.finished.color
        case "limit": return Theme.deny
        default: return Theme.secondary
        }
    }

    // MARK: Activity

    private var activityCard: some View {
        Card {
            sectionTitle("Actividad", count: nil)
            if model.activity.isEmpty {
                Text("Lo que hagan tus sesiones irá apareciendo aquí.")
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(model.activity.prefix(30)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(Theme.amber)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text).font(.subheadline).lineLimit(2)
                            Text("\(item.project) · \(item.at.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title).font(.title2.bold())
            if let count, count > 0 {
                Text("\(count)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(Theme.amber, in: Capsule())
            }
        }
    }
}

// MARK: - One permission request

struct ApprovalRow: View {
    @Environment(AppModel.self) private var model
    let approval: Approval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(approval.project, systemImage: "folder.fill")
                    .font(.headline)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(AppModel.approvalLifetime - ctx.date.timeIntervalSince(approval.receivedAt)))
                    Text("\(left) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(left < 20 ? Theme.deny : Theme.secondary)
                }
            }
            Text(approval.tool)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.amber)
            Text(approval.target)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .lineLimit(8)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 12) {
                Button {
                    model.decide(approval, allow: false)
                } label: {
                    Text("Denegar").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(Theme.deny)

                Button {
                    model.decide(approval, allow: true)
                } label: {
                    Text("Permitir").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.allow)
            }
            .disabled(approval.sending)
            if approval.sending {
                Text("Enviando…").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}
