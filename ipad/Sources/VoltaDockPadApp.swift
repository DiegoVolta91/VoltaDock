import SwiftUI

@main
struct VoltaDockPadApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // A voltadock://pair link opened from the camera or a message.
                    model.pair(with: url.absoluteString)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            model.setActive(phase == .active)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if model.pairing == nil {
                PairingView()
            } else {
                DashboardView()
            }
        }
        .tint(Theme.amber)
    }
}

enum Theme {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)   // #0B0C0E
    static let card = Color(red: 0.086, green: 0.094, blue: 0.11)
    static let cardBorder = Color.white.opacity(0.07)
    static let amber = Color(red: 1, green: 0.69, blue: 0.125)
    static let allow = Color(red: 0.133, green: 0.773, blue: 0.369)        // #22C55E
    static let deny = Color(red: 0.957, green: 0.314, blue: 0.369)         // #F4505E
    static let secondary = Color.white.opacity(0.55)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardBorder))
    }
}
