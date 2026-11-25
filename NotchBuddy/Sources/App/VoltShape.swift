import SwiftUI

// Volt — VoltaDock's character: a small battery with a lightning-bolt antenna.
// Shared drawing pieces used by BotEngine, GreetingCanvasView and
// UploadCanvasView. Mirrors windows/src/mochi/volt.ts; keep the two in step
// (same proportions, same colours).
//
// Everything is drawn around the body centre. `hw`/`hh` are the half-width and
// half-height of the battery case, without cap and bolt.

enum Volt {
    /// Half-width of the case, as a fraction of the engine's R.
    static let hw: CGFloat = 0.66
    /// Half-height of the case, as a fraction of R.
    static let hh: CGFloat = 0.8
    /// Corner radius, as a fraction of min(hw, hh).
    static let corner: CGFloat = 0.5
    /// How far the case centre moves down (fraction of R) so cap and bolt fit above it.
    static let drop: CGFloat = 0.1

    static let amber    = Color(red: 1, green: 0.69, blue: 0.125)        // #FFB020
    static let amberDim = Color(red: 0.725, green: 0.506, blue: 0.11)    // #B9811C
    static let spark    = Color(red: 0.361, green: 0.882, blue: 1)       // #5CE1FF
    static let capGray  = Color(red: 0.682, green: 0.714, blue: 0.769)   // #AEB6C4
    static let track    = Color(red: 0.165, green: 0.184, blue: 0.227)   // #2A2F3A

    /// Rounded-rect battery case.
    static func bodyPath(hw: CGFloat, hh: CGFloat, cornerFrac: CGFloat = Volt.corner) -> Path {
        let r = min(hw, hh) * cornerFrac
        return Path(roundedRect: CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2),
                    cornerSize: CGSize(width: r, height: r), style: .continuous)
    }

    struct AntennaStyle {
        var color: Color
        var glow: CGFloat = 0      // blur radius in points, 0 = none
        var sway: CGFloat = 0      // radians
        var alpha: CGFloat = 1     // 0…1
        var cap: Color = Volt.capGray
    }

    /// Cap (battery terminal) on top of the case and the bolt rising from it.
    /// Total height above the case: about 0.72 × hh.
    static func drawAntenna(_ context: GraphicsContext, hw: CGFloat, hh: CGFloat, style s: AntennaStyle) {
        guard s.alpha > 0.01 else { return }
        var ctx = context
        ctx.opacity *= Double(min(1, s.alpha))
        let capW = hw * 0.72
        let capH = hh * 0.11
        let cap = Path(roundedRect: CGRect(x: -capW / 2, y: -hh - capH, width: capW, height: capH + hh * 0.04),
                       cornerSize: CGSize(width: capH * 0.35, height: capH * 0.35))
        ctx.fill(cap, with: .color(s.cap))

        let u = hh * 0.62
        ctx.translateBy(x: 0, y: -hh - capH * 0.9)
        ctx.rotate(by: .radians(Double(s.sway)))
        var bolt = Path()
        let pts: [(CGFloat, CGFloat)] = [(-0.05, 0), (-0.25, -0.5), (-0.03, -0.5), (-0.17, -1.0),
                                         (0.31, -0.33), (0.08, -0.33), (0.19, 0)]
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: p.0 * u, y: p.1 * u)
            if i == 0 { bolt.move(to: pt) } else { bolt.addLine(to: pt) }
        }
        bolt.closeSubpath()
        if s.glow > 0 {
            var glowCtx = ctx
            glowCtx.addFilter(.blur(radius: s.glow * 0.5))
            glowCtx.opacity *= 0.8
            glowCtx.fill(bolt, with: .color(s.color))
        }
        ctx.fill(bolt, with: .color(s.color))
    }

    /// The charge bar on Volt's belly: a dark track with four cells. `level` 0…1
    /// lights cells left to right; a partly lit cell is drawn shorter and fainter.
    static func drawChargeBar(_ context: GraphicsContext, hw: CGFloat, hh: CGFloat,
                              level: CGFloat, color: Color, alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        var ctx = context
        ctx.opacity *= Double(alpha)
        let w = hw * 1.34
        let h = hh * 0.36
        let top = hh * 0.3
        ctx.fill(Path(roundedRect: CGRect(x: -w / 2, y: top, width: w, height: h),
                      cornerSize: CGSize(width: h * 0.32, height: h * 0.32)),
                 with: .color(track))
        let pad = h * 0.17
        let cells = 4
        let cw = (w - pad * CGFloat(cells + 1)) / CGFloat(cells)
        let lit = max(0, min(1, level)) * CGFloat(cells)
        let ch = h - pad * 2
        for i in 0..<cells {
            let f = max(0, min(1, lit - CGFloat(i)))
            if f <= 0.02 { continue }
            let rect = CGRect(x: -w / 2 + pad + CGFloat(i) * (cw + pad), y: top + pad,
                              width: cw * max(0.25, f), height: ch)
            ctx.fill(Path(roundedRect: rect, cornerSize: CGSize(width: ch * 0.25, height: ch * 0.25)),
                     with: .color(color.opacity(Double(0.35 + 0.65 * f))))
        }
    }

    // MARK: - Core Graphics versions (GreetingCanvasView draws with CGContext)

    static func cgBodyPath(hw: CGFloat, hh: CGFloat, cornerFrac: CGFloat = Volt.corner) -> CGPath {
        let r = min(hw, hh) * cornerFrac
        return CGPath(roundedRect: CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2),
                      cornerWidth: r, cornerHeight: r, transform: nil)
    }

    static func drawAntenna(_ ctx: CGContext, hw: CGFloat, hh: CGFloat,
                            color: CGColor, glow: CGFloat = 0, sway: CGFloat = 0) {
        let capW = hw * 0.72
        let capH = hh * 0.11
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0.682, green: 0.714, blue: 0.769, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -capW / 2, y: -hh - capH, width: capW, height: capH + hh * 0.04),
                           cornerWidth: capH * 0.35, cornerHeight: capH * 0.35, transform: nil))
        ctx.fillPath()
        let u = hh * 0.62
        ctx.translateBy(x: 0, y: -hh - capH * 0.9)
        ctx.rotate(by: sway)
        if glow > 0 { ctx.setShadow(offset: .zero, blur: glow, color: color) }
        let pts: [(CGFloat, CGFloat)] = [(-0.05, 0), (-0.25, -0.5), (-0.03, -0.5), (-0.17, -1.0),
                                         (0.31, -0.33), (0.08, -0.33), (0.19, 0)]
        ctx.beginPath()
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: p.0 * u, y: p.1 * u)
            if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
        }
        ctx.closePath()
        ctx.setFillColor(color)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func drawChargeBar(_ ctx: CGContext, hw: CGFloat, hh: CGFloat, level: CGFloat, color: CGColor) {
        let w = hw * 1.34
        let h = hh * 0.36
        let top = hh * 0.3
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0.165, green: 0.184, blue: 0.227, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -w / 2, y: top, width: w, height: h),
                           cornerWidth: h * 0.32, cornerHeight: h * 0.32, transform: nil))
        ctx.fillPath()
        let pad = h * 0.17
        let cw = (w - pad * 5) / 4
        let ch = h - pad * 2
        let lit = max(0, min(1, level)) * 4
        for i in 0..<4 {
            let f = max(0, min(1, lit - CGFloat(i)))
            if f <= 0.02 { continue }
            ctx.setFillColor(color.copy(alpha: 0.35 + 0.65 * f) ?? color)
            let rect = CGRect(x: -w / 2 + pad + CGFloat(i) * (cw + pad), y: top + pad,
                              width: cw * max(0.25, f), height: ch)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: ch * 0.25, cornerHeight: ch * 0.25, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}
