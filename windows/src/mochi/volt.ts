// Volt — VoltaDock's character: a small battery with a lightning-bolt antenna.
// Shared drawing pieces used by the island engine, the launch greeting and the
// upload canvas. Mirrors NotchBuddy/Sources/App/VoltShape.swift; keep the two in
// step (same proportions, same colours).
//
// Everything is drawn around the body centre. `hw`/`hh` are the half-width and
// half-height of the body (the battery case, without cap and bolt).

/** Body proportions, as a fraction of the engine's R. */
export const VOLT = {
  /** half-width / R */
  hw: 0.66,
  /** half-height / R */
  hh: 0.8,
  /** corner radius / min(hw, hh) */
  corner: 0.5,
  /** body centre shift down / R, so cap + bolt fit above it */
  drop: 0.1,
} as const;

export const AMBER: readonly [number, number, number] = [1, 0.69, 0.125]; // #FFB020
export const AMBER_DIM = "rgb(185,129,28)"; // #B9811C
export const SPARK = "rgb(92,225,255)"; // #5CE1FF

/** Rounded-rect battery case. */
export function voltBodyPath(hw: number, hh: number, cornerFrac: number = VOLT.corner): Path2D {
  const p = new Path2D();
  const r = Math.min(hw, hh) * cornerFrac;
  p.roundRect(-hw, -hh, hw * 2, hh * 2, r);
  return p;
}

export interface AntennaStyle {
  /** CSS colour of the bolt. */
  color: string;
  /** Glow radius in px (0 = none). */
  glow: number;
  /** Sway angle in radians. */
  sway: number;
  /** 0…1, fades the cap and bolt (e.g. while morphing into the upload box). */
  alpha: number;
  /** Cap colour (CSS). */
  cap?: string;
}

/**
 * Cap (battery terminal) on top of the case, and the lightning bolt rising from
 * it. Drawn in body space, before or after the body; it never overlaps it.
 * Total height above the body: about 0.72 × hh.
 */
export function drawVoltAntenna(x: CanvasRenderingContext2D, hw: number, hh: number, s: AntennaStyle) {
  if (s.alpha <= 0.01) return;
  x.save();
  x.globalAlpha *= Math.min(1, s.alpha);
  // Cap
  const capW = hw * 0.72;
  const capH = hh * 0.11;
  x.fillStyle = s.cap ?? "rgb(174,182,196)";
  x.beginPath();
  x.roundRect(-capW / 2, -hh - capH, capW, capH + hh * 0.04, capH * 0.35);
  x.fill();
  // Bolt — a 7-point zigzag, unit height u, pivoting at the cap
  const u = hh * 0.62;
  x.translate(0, -hh - capH * 0.9);
  x.rotate(s.sway);
  if (s.glow > 0) {
    x.shadowColor = s.color;
    x.shadowBlur = s.glow;
  }
  x.fillStyle = s.color;
  x.beginPath();
  x.moveTo(-0.05 * u, 0);
  x.lineTo(-0.25 * u, -0.5 * u);
  x.lineTo(-0.03 * u, -0.5 * u);
  x.lineTo(-0.17 * u, -1.0 * u);
  x.lineTo(0.31 * u, -0.33 * u);
  x.lineTo(0.08 * u, -0.33 * u);
  x.lineTo(0.19 * u, 0);
  x.closePath();
  x.fill();
  x.restore();
}

/**
 * The charge bar on Volt's belly: a dark track with four cells. `level` 0…1
 * lights cells left to right; a partly lit cell is drawn shorter and fainter.
 */
export function drawChargeBar(
  x: CanvasRenderingContext2D, hw: number, hh: number,
  level: number, color: string, alpha = 1,
) {
  if (alpha <= 0.01) return;
  const w = hw * 1.34;
  const h = hh * 0.36;
  const top = hh * 0.3;
  x.save();
  x.globalAlpha *= alpha;
  x.fillStyle = "rgb(42,47,58)";
  x.beginPath();
  x.roundRect(-w / 2, top, w, h, h * 0.32);
  x.fill();
  const pad = h * 0.17;
  const cells = 4;
  const cw = (w - pad * (cells + 1)) / cells;
  const lit = Math.max(0, Math.min(1, level)) * cells;
  x.fillStyle = color;
  for (let i = 0; i < cells; i++) {
    const f = Math.max(0, Math.min(1, lit - i));
    if (f <= 0.02) continue;
    x.globalAlpha = alpha * (0.35 + 0.65 * f);
    x.beginPath();
    x.roundRect(-w / 2 + pad + i * (cw + pad), top + pad, cw * Math.max(0.25, f), h - pad * 2, (h - pad * 2) * 0.25);
    x.fill();
  }
  x.restore();
}
