// Draws Volt, VoltaDock's character, into every icon the apps need — the
// Windows PNG/ICO set for Tauri and the macOS app icon and menu bar template.
// No dependencies: the icons are rasterised here and encoded with node:zlib, so
// the icons stay "drawn in code" like the character itself.
//
//   node scripts/gen-icons.mjs        (from windows/, or `npm run icons`)
//
// Geometry matches src/mochi/volt.ts and NotchBuddy/Sources/App/VoltShape.swift,
// in "Volt units" where the engine's R is 50.

import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "src-tauri", "icons");
const MAC = join(HERE, "..", "..", "NotchBuddy", "Assets.xcassets");

// ── Volt ──────────────────────────────────────────────────────────────────────

const BODY_TOP = [244, 246, 250];
const BODY_BOTTOM = [195, 202, 215];
const INK = [27, 31, 41];
const TRACK = [42, 47, 58];
const AMBER = [255, 176, 32];
const CAP = [174, 182, 196];
const RIM = [10, 12, 16];
const BG_TOP = [51, 64, 90];
const BG_BOTTOM = [21, 26, 36];

const SS = 4; // supersampling factor per axis

const HW = 33, HH = 40, CORNER = 16.5;
const CAP_W = HW * 0.72, CAP_H = HH * 0.11;
const U = HH * 0.62; // bolt height
const BOLT_Y = -HH - CAP_H * 0.9;
const BOLT = [[-0.05, 0], [-0.25, -0.5], [-0.03, -0.5], [-0.17, -1], [0.31, -0.33], [0.08, -0.33], [0.19, 0]]
  .map(([x, y]) => [x * U, BOLT_Y + y * U]);
const EYE_X = Math.sin(0.37) * Math.cos(0.3) * HW, EYE_Y = -Math.sin(0.3) * HH;
const EYE_W = 12.5 * Math.cos(0.37), EYE_H = 13.5 * Math.cos(0.3);
const BAR_W = HW * 1.34, BAR_H = HH * 0.36, BAR_TOP = HH * 0.3, BAR_PAD = BAR_H * 0.17;
const CELL_W = (BAR_W - BAR_PAD * 5) / 4;
/** Vertical extent of the whole character, for centring. */
const TOP = BOLT_Y - U, BOTTOM = HH;

function inRoundRect(x, y, cx, cy, w, h, r) {
  const dx = Math.abs(x - cx) - (w / 2 - r);
  const dy = Math.abs(y - cy) - (h / 2 - r);
  if (dx <= 0 && Math.abs(y - cy) <= h / 2) return true;
  if (dy <= 0 && Math.abs(x - cx) <= w / 2) return true;
  return dx * dx + dy * dy <= r * r && dx > 0 && dy > 0;
}

function inPoly(x, y, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

const lerp3 = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

/**
 * Colour of one sample in Volt units, or null for transparent.
 * mode: "full" (colour), "template" (black silhouette with eyes and bar cut out).
 * rim: dark outline width in units (0 = none).
 */
function sample(x, y, mode, rim) {
  const inBody = inRoundRect(x, y, 0, 0, HW * 2, HH * 2, CORNER);
  const inCap = inRoundRect(x, y, 0, -HH - CAP_H / 2 + HH * 0.02, CAP_W, CAP_H + HH * 0.04, CAP_H * 0.35);
  const inBolt = inPoly(x, y, BOLT);
  if (mode === "template") {
    if (inBolt || inCap) return [0, 0, 0];
    if (!inBody) return null;
    for (const sd of [-1, 1]) if (inRoundRect(x, y, sd * EYE_X, EYE_Y, EYE_W, EYE_H, EYE_W / 2)) return null;
    if (inRoundRect(x, y, 0, BAR_TOP + BAR_H / 2, BAR_W, BAR_H, BAR_H * 0.32)) {
      for (let i = 0; i < 3; i++) {
        const cx = -BAR_W / 2 + BAR_PAD + i * (CELL_W + BAR_PAD) + CELL_W / 2;
        if (inRoundRect(x, y, cx, BAR_TOP + BAR_H / 2, CELL_W, BAR_H - BAR_PAD * 2, 2)) return [0, 0, 0];
      }
      return null;
    }
    return [0, 0, 0];
  }
  if (inBolt) return AMBER;
  if (inCap) return CAP;
  if (inBody) {
    for (const sd of [-1, 1]) if (inRoundRect(x, y, sd * EYE_X, EYE_Y, EYE_W, EYE_H, EYE_W / 2)) return INK;
    if (inRoundRect(x, y, 0, BAR_TOP + BAR_H / 2, BAR_W, BAR_H, BAR_H * 0.32)) {
      for (let i = 0; i < 3; i++) {
        const cx = -BAR_W / 2 + BAR_PAD + i * (CELL_W + BAR_PAD) + CELL_W / 2;
        if (inRoundRect(x, y, cx, BAR_TOP + BAR_H / 2, CELL_W, BAR_H - BAR_PAD * 2, (BAR_H - BAR_PAD * 2) * 0.25)) return AMBER;
      }
      return TRACK;
    }
    const t = Math.min(1, Math.max(0, ((x + y) / (HW + HH) + 1) / 2));
    return lerp3(BODY_TOP, BODY_BOTTOM, t);
  }
  if (rim > 0) {
    const nearBody = inRoundRect(x, y, 0, 0, HW * 2 + rim * 2, HH * 2 + rim * 2, CORNER + rim);
    const nearCap = inRoundRect(x, y, 0, -HH - CAP_H / 2 + HH * 0.02, CAP_W + rim * 2, CAP_H + HH * 0.04 + rim * 2, CAP_H * 0.35 + rim);
    if (nearBody || nearCap) return RIM;
  }
  return null;
}

/**
 * Renders a w×h RGBA image. `fit` is the fraction of the height Volt fills.
 * `bg`: draw the macOS-style rounded-square background.
 */
function render(w, h, { fit = 0.92, mode = "full", rim = 0, bg = false } = {}) {
  const px = new Uint8Array(w * h * 4);
  const scale = (h * fit) / (BOTTOM - TOP);
  const midY = (TOP + BOTTOM) / 2;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const X = x + (sx + 0.5) / SS, Y = y + (sy + 0.5) / SS;
          let c = sample((X - w / 2) / scale, (Y - h / 2) / scale + midY, mode, rim);
          if (!c && bg) {
            // macOS icon grid: 824/1024 rounded square, radius ≈ 22.5 %
            const m = w * 100 / 1024, side = w - m * 2;
            if (inRoundRect(X, Y, w / 2, h / 2, side, side, side * 0.225)) c = lerp3(BG_TOP, BG_BOTTOM, (Y - m) / side);
          }
          if (!c) continue;
          r += c[0]; g += c[1]; b += c[2]; a++;
        }
      }
      if (!a) continue;
      const o = (y * w + x) * 4;
      px[o] = Math.round(r / a);
      px[o + 1] = Math.round(g / a);
      px[o + 2] = Math.round(b / a);
      px[o + 3] = Math.round((a / (SS * SS)) * 255);
    }
  }
  return px;
}

// ── PNG ───────────────────────────────────────────────────────────────────────

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encodePNG(size, rgba, height = size) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc(height * (size * 4 + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    Buffer.from(rgba.buffer, y * size * 4, size * 4).copy(raw, y * (size * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ── ICO (PNG-in-ICO, Vista and later) ─────────────────────────────────────────

function encodeICO(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(entries.length, 4);
  const dir = Buffer.alloc(16 * entries.length);
  let offset = header.length + dir.length;
  entries.forEach((e, i) => {
    const o = i * 16;
    dir[o] = e.size >= 256 ? 0 : e.size;
    dir[o + 1] = e.size >= 256 ? 0 : e.size;
    dir[o + 2] = 0;
    dir[o + 3] = 0;
    dir.writeUInt16LE(1, o + 4);
    dir.writeUInt16LE(32, o + 6);
    dir.writeUInt32LE(e.png.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += e.png.length;
  });
  return Buffer.concat([header, dir, ...entries.map((e) => e.png)]);
}

// ── Go ────────────────────────────────────────────────────────────────────────

mkdirSync(OUT, { recursive: true });

// Windows: Volt on its own with a thin dark rim, so the tray icon reads on light taskbars.
const png = (size) => encodePNG(size, render(size, size, { fit: 0.94, rim: 2.5 }));

const files = {
  "32x32.png": png(32),
  "128x128.png": png(128),
  "128x128@2x.png": png(256),
  "icon.png": png(512),
};
for (const [name, data] of Object.entries(files)) {
  writeFileSync(join(OUT, name), data);
  console.log(`windows/${name} — ${data.length} bytes`);
}

const ico = encodeICO([16, 24, 32, 48, 64, 128, 256].map((size) => ({ size, png: png(size) })));
writeFileSync(join(OUT, "icon.ico"), ico);
console.log(`windows/icon.ico — ${ico.length} bytes`);

// macOS app icon: Volt on a dark rounded square, at every size the asset catalog lists.
const appIcon = join(MAC, "AppIcon.appiconset");
for (const base of [16, 32, 128, 256, 512]) {
  for (const k of [1, 2]) {
    const size = base * k;
    const name = `icon_${base}x${base}${k === 2 ? "@2x" : ""}.png`;
    writeFileSync(join(appIcon, name), encodePNG(size, render(size, size, { fit: 0.6, bg: true })));
    console.log(`mac/${name}`);
  }
}

// macOS menu bar: a black template silhouette (24×18 pt), eyes and charge bar cut out.
const menuBar = join(MAC, "MenuBarIcon.imageset");
for (const k of [1, 2, 3]) {
  const name = `menubar${k === 1 ? "" : `@${k}x`}.png`;
  writeFileSync(join(menuBar, name), encodePNG(24 * k, render(24 * k, 18 * k, { fit: 1, mode: "template" }), 18 * k));
  console.log(`mac/${name}`);
}
