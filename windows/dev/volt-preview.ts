// Dev-only page: every Volt state side by side, plus the launch greeting.
// `npx vite` then open /dev/volt-preview.html.
import { BotEngine } from "../src/mochi/engine";
import { Greeting } from "../src/mochi/greeting";
import type { BotStateName } from "../src/core/layout";

const states: BotStateName[] = ["idle", "working", "thinking", "searching", "approval", "question", "error", "finished", "ratelimit", "sleeping", "dizzy"];
const grid = document.getElementById("grid")!;
const bots = states.map((st) => {
  const fig = document.createElement("figure");
  const c = document.createElement("canvas");
  c.width = 120 * devicePixelRatio; c.height = 120 * devicePixelRatio;
  c.style.width = c.style.height = "120px";
  const cap = document.createElement("figcaption");
  cap.textContent = st;
  fig.append(c, cap);
  grid.append(fig);
  const e = new BotEngine();
  e.setState(st, true);
  return { e, ctx: c.getContext("2d")! };
});
const g = new Greeting();
const gctx = (document.getElementById("greet") as HTMLCanvasElement).getContext("2d")!;
g.start();
let last = performance.now();
function frame(t: number) {
  const dt = (t - last) / 1000; last = t;
  for (const b of bots) {
    b.e.update(dt);
    b.ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
    b.ctx.clearRect(0, 0, 120, 120);
    b.e.draw(b.ctx, 120, 120);
  }
  gctx.clearRect(0, 0, 640, 150);
  g.draw(gctx);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
