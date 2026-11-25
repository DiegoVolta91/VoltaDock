import SwiftUI

// MARK: - Volt
// VoltaDock's character: a small battery with a lightning-bolt antenna, drawn in
// code. Same proportions and colours as windows/src/mochi/volt.ts (and the Mac's
// VoltShape.swift once it lands); this is a lighter version of the island's
// engine — breathing, blinking, a swaying bolt and a charge bar — enough for a
// status screen.

enum VoltMood: Equatable {
    case idle, working, thinking, approval, finished, sleeping

    var color: Color {
        switch self {
        case .idle: return Color(red: 1, green: 0.69, blue: 0.125)          // amber #FFB020
        case .working: return Color(red: 0.231, green: 0.62, blue: 1)
        case .thinking: return Color(red: 0.545, green: 0.361, blue: 0.965)
        case .approval: return Color(red: 0.961, green: 0.647, blue: 0.141)
        case .finished: return Color(red: 0.204, green: 0.831, blue: 0.6)
        case .sleeping: return Color(red: 0.58, green: 0.635, blue: 0.722)
        }
    }
}

struct VoltView: View {
    var mood: VoltMood
    var size: CGFloat = 140

    private static let spark = Color(red: 0.361, green: 0.882, blue: 1)        // #5CE1FF
    private static let amberDim = Color(red: 0.725, green: 0.506, blue: 0.11)  // #B9811C
    private static let bodyTop = Color(red: 0.929, green: 0.929, blue: 0.937)  // #EDEDEF
    private static let bodyBottom = Color(red: 0.769, green: 0.773, blue: 0.792) // #C4C5CA
    private static let ink = Color(red: 0.102, green: 0.078, blue: 0.071)      // #1A1412
    private static let cap = Color(red: 0.682, green: 0.714, blue: 0.769)
    private static let track = Color(red: 0.165, green: 0.184, blue: 0.227)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, canvas in
                draw(ctx, canvas, t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size * 1.25)
        .accessibilityLabel("Volt")
    }

    private func draw(_ ctx: GraphicsContext, _ canvas: CGSize, t: Double) {
        let W = Double(canvas.width)
        let H = Double(canvas.height)
        let R: Double = W * 0.42
        let hw: Double = R * 0.66
        let hh: Double = R * 0.8
        let breathe: Double = mood == .sleeping ? 0.012 * sin(t * 1.2) : 0.02 * sin(t * 2.2)
        let bounce: Double = mood == .approval ? abs(sin(t * 5)) * R * 0.06 : 0
        let cx: Double = W / 2
        let cy: Double = H * 0.6 - bounce

        var c = ctx
        c.translateBy(x: cx, y: cy)
        c.scaleBy(x: 1 - breathe * 0.5, y: 1 + breathe)

        drawAntenna(c, hw: hw, hh: hh, R: R, t: t)

        // Battery case
        let bodyRect = CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2)
        let body = Path(roundedRect: bodyRect, cornerRadius: min(hw, hh) * 0.5, style: .continuous)
        c.fill(body, with: .linearGradient(
            Gradient(colors: [Self.bodyTop, Self.bodyBottom]),
            startPoint: CGPoint(x: 0, y: -hh), endPoint: CGPoint(x: 0, y: hh)))
        if mood != .idle && mood != .sleeping {
            c.fill(body, with: .color(mood.color.opacity(0.18)))
        }

        drawEyes(c, hw: hw, hh: hh, R: R, t: t)
        drawChargeBar(c, hw: hw, hh: hh, t: t)
    }

    private func drawAntenna(_ ctx: GraphicsContext, hw: Double, hh: Double, R: Double, t: Double) {
        var c = ctx
        let capW = hw * 0.72
        let capH = hh * 0.11
        c.fill(Path(roundedRect: CGRect(x: -capW / 2, y: -hh - capH, width: capW, height: capH + hh * 0.04),
                    cornerRadius: capH * 0.35), with: .color(Self.cap))

        var sway = sin(t * 1.3) * 0.08
        if mood == .working { sway += sin(t * 9) * 0.05 }
        if mood == .sleeping { sway = 0.35 }
        let color: Color
        var glow = 0.0
        switch mood {
        case .idle: color = Self.amberDim
        case .sleeping: color = Color(red: 0.43, green: 0.41, blue: 0.36)
        case .approval:
            let on = sin(t * 10) > 0
            color = on ? Self.spark : mood.color
            glow = R * (on ? 0.4 : 0.2)
        default:
            color = mood.color
            glow = R * (0.2 + 0.08 * sin(t * 8))
        }

        let u = hh * 0.62
        c.translateBy(x: 0, y: -hh - capH * 0.9)
        c.rotate(by: .radians(sway))
        var bolt = Path()
        bolt.move(to: CGPoint(x: -0.05 * u, y: 0))
        bolt.addLine(to: CGPoint(x: -0.25 * u, y: -0.5 * u))
        bolt.addLine(to: CGPoint(x: -0.03 * u, y: -0.5 * u))
        bolt.addLine(to: CGPoint(x: -0.17 * u, y: -1.0 * u))
        bolt.addLine(to: CGPoint(x: 0.31 * u, y: -0.33 * u))
        bolt.addLine(to: CGPoint(x: 0.08 * u, y: -0.33 * u))
        bolt.addLine(to: CGPoint(x: 0.19 * u, y: 0))
        bolt.closeSubpath()
        if glow > 0 { c.addFilter(.shadow(color: color, radius: glow / 2)) }
        c.fill(bolt, with: .color(color))
    }

    private func drawEyes(_ c: GraphicsContext, hw: Double, hh: Double, R: Double, t: Double) {
        let ew = R * 0.25 * (mood == .approval ? 1.16 : 1)
        let eh = R * 0.27 * (mood == .approval ? 1.12 : 1)
        let ey = -0.3 * hh
        // Blink: a short close every ~4 s.
        let phase = t.truncatingRemainder(dividingBy: 4.2)
        let open = mood == .sleeping ? 0.0 : (phase < 0.14 ? abs(phase - 0.07) / 0.07 : 1.0)
        for side in [-1.0, 1.0] {
            let ex = side * 0.36 * hw
            if mood == .finished {
                // Happy arcs
                var arc = Path()
                arc.addArc(center: CGPoint(x: ex, y: ey + eh * 0.15), radius: ew * 0.45,
                           startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                c.stroke(arc, with: .color(Self.ink), style: StrokeStyle(lineWidth: ew * 0.28, lineCap: .round))
            } else {
                let h = max(eh * open, ew * 0.3)
                let rect = CGRect(x: ex - ew / 2, y: ey - h / 2, width: ew, height: h)
                c.fill(Path(roundedRect: rect, cornerRadius: min(ew, h) / 2), with: .color(Self.ink))
            }
        }
    }

    private func drawChargeBar(_ c: GraphicsContext, hw: Double, hh: Double, t: Double) {
        let w = hw * 1.34
        let h = hh * 0.36
        let top = hh * 0.3
        c.fill(Path(roundedRect: CGRect(x: -w / 2, y: top, width: w, height: h), cornerRadius: h * 0.32),
               with: .color(Self.track))
        let level: Double
        var color = mood.color
        switch mood {
        case .working: level = (t * 0.35).truncatingRemainder(dividingBy: 1.15)
        case .thinking: level = 0.5 + 0.25 * sin(t * 2)
        case .approval:
            level = 0.75
            if sin(t * 10) > 0 { color = Self.spark }
        case .finished: level = 1
        case .sleeping:
            level = 0.25
            color = Color(red: 0.43, green: 0.47, blue: 0.55)
        case .idle: level = 0.5
        }
        let pad = h * 0.17
        let cells = 4.0
        let cw = (w - pad * (cells + 1)) / cells
        let lit = max(0, min(1, level)) * cells
        for i in 0..<4 {
            let f = max(0, min(1, lit - Double(i)))
            if f <= 0.02 { continue }
            let rect = CGRect(x: -w / 2 + pad + Double(i) * (cw + pad), y: top + pad,
                              width: cw * max(0.25, f), height: h - pad * 2)
            c.fill(Path(roundedRect: rect, cornerRadius: (h - pad * 2) * 0.25),
                   with: .color(color.opacity(0.35 + 0.65 * f)))
        }
    }
}

#Preview {
    HStack {
        VoltView(mood: .idle)
        VoltView(mood: .approval)
        VoltView(mood: .finished)
    }
    .padding()
    .background(Color.black)
}
