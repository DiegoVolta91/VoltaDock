// Views for the Hoy pill — DOM ports of TodayViews.swift: the overview card
// (focus timer + quick add), the full list, the alert card for reminders and
// focus blocks, and the thin countdown bar under the compact island.

import { h, svg, clear, dot } from "./dom";
import { ICONS } from "./icons";
import { State } from "../core/state";
import { Bridge } from "../core/bridge";
import { Sound } from "../core/sound";
import { washRGBA } from "../core/layout";
import { tr } from "../i18n";
import {
  Today, FOCUS_MS, clock, dueLabel, fraction, isPaused, remaining, type TodayItem,
} from "../core/today";

export const TODAY_COLOR = "#2DD4BF";
const FOCUS_COLOR = "#F5A524";
const REST_COLOR = "#34D399";

// ── One-second ticker ─────────────────────────────────────────────────────────
// Runs only while a block is actually counting down; every clock on screen
// registers here instead of keeping the island's frame loop awake.

const tickers = new Set<() => void>();
let tickHandle: number | null = null;

function ensureTicker() {
  const running = Today.focus.phase !== "idle" && !isPaused(Today.focus);
  if (running && tickHandle == null) {
    tickHandle = window.setInterval(() => {
      for (const fn of tickers) fn();
      if (Today.focus.phase === "idle" || isPaused(Today.focus)) ensureTicker();
    }, 1000);
  } else if (!running && tickHandle != null) {
    window.clearInterval(tickHandle);
    tickHandle = null;
  }
}

// ── Overview card ─────────────────────────────────────────────────────────────

export interface TodayCard {
  el: HTMLElement;
  sync(): void;
  toggleList(): void;
}

function chip(label: string | null, icon: string, accent: string | null, onClick: () => void): HTMLElement {
  const el = h("button", { class: label ? "today-chip" : "today-chip icon", onclick: onClick }, svg(icon, 8));
  if (label) el.append(h("span", { text: label }));
  if (accent) {
    el.style.color = accent;
    el.style.setProperty("--chip-bg", `${accent}1a`);
    el.style.setProperty("--chip-bg-hover", `${accent}33`);
  }
  return el;
}

export function buildTodayCard(): TodayCard {
  // Main face
  const summary = h("button", { class: "today-summary", onclick: () => toggleList() });
  const head = h("div", { class: "int-head" }, dot(TODAY_COLOR, 7), h("b", { text: tr.today.name }), summary);

  const clockEl = h("span", { class: "today-clock" });
  const caption = h("span", { class: "today-caption" });
  const chips = h("div", { class: "today-chips" });
  const focusRow = h("div", { class: "today-focus" }, clockEl, caption, h("div", { class: "grow" }), chips);

  const addIcon = h("span", { class: "today-add-icon" }, svg(ICONS.plus, 9));
  const flashEl = h("span", { class: "today-flash" });
  const input = h("input", {
    class: "today-input",
    type: "text",
    spellcheck: "false",
    autocomplete: "off",
    placeholder: tr.today.addPlaceholder,
  }) as HTMLInputElement;
  let asGoal = false;
  const goalBtn = h("button", {
    class: "today-goal-btn",
    title: tr.today.goalToggle,
    type: "button",
    onclick: (e: Event) => {
      e.preventDefault();
      asGoal = !asGoal;
      goalBtn.classList.toggle("on", asGoal);
      input.placeholder = asGoal ? tr.today.goalPlaceholder : tr.today.addPlaceholder;
    },
  }, svg(ICONS.check, 7, { stroke: 3 }), h("span", { text: tr.today.goal }));
  const add = h("label", { class: "today-add" }, addIcon, flashEl, input, goalBtn);

  const face = h("div", { class: "int-card today-card" }, head, focusRow, add);

  // List
  const clearDone = h("button", { class: "link-btn", style: `color:${TODAY_COLOR}d9`, text: tr.today.clearDone, onclick: () => Today.clearDone() });
  const back = h("button", { class: "icon-btn", title: tr.today.back, onclick: () => toggleList() }, svg(ICONS.chevronLeft, 9, { stroke: 2.4 }));
  const listHead = h("div", { class: "today-list-head" }, back, h("b", { text: tr.today.name }), h("div", { class: "grow" }), clearDone);
  const rows = h("div", { class: "today-rows" });
  const list = h("div", { class: "today-list" }, listHead, rows);

  const el = h("div", { class: "today-host" }, face);
  let listOpen = false;
  let chipsKey = "";
  let rowsKey = "";
  let flashTimer: number | null = null;

  // Typing needs the keyboard; the island is a no-focus window the rest of the time.
  input.addEventListener("focus", () => void Bridge.focusWindow(true));
  input.addEventListener("blur", () => {
    if (State.view !== "prompt") void Bridge.focusWindow(false);
  });
  add.addEventListener("mousedown", () => {
    void Bridge.focusWindow(true);
    window.setTimeout(() => input.focus(), 0);
  });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      input.value = "";
      input.blur();
      return;
    }
    if (e.key !== "Enter") return;
    const item = Today.add(input.value, asGoal);
    if (!item) return;
    input.value = "";
    add.classList.remove("typing");
    flash(`${tr.today.added}${item.dueAt != null ? ` · ${dueLabel(item.dueAt)}` : ""}`);
    Sound.play("pop");
  });
  // While typing, the card must not auto-close under your fingers.
  input.addEventListener("input", () => {
    State.lastActivity = performance.now();
    add.classList.toggle("typing", input.value.length > 0);
  });

  function flash(text: string) {
    flashEl.textContent = text;
    add.classList.add("flash");
    if (flashTimer != null) window.clearTimeout(flashTimer);
    flashTimer = window.setTimeout(() => add.classList.remove("flash"), 1800);
  }

  function toggleList() {
    listOpen = !listOpen;
    rowsKey = "";
    el.replaceChildren(listOpen ? list : face);
    sync();
  }

  function paintClock() {
    const f = Today.focus;
    clockEl.textContent = clock(f.phase === "idle" ? FOCUS_MS : remaining(f));
    clockEl.style.opacity = isPaused(f) ? "0.6" : "1";
    clockEl.style.color = f.phase === "idle" ? "var(--dim-3)" : "";
  }
  tickers.add(paintClock);

  function syncFace() {
    const open = Today.openItems.length;
    const next = Today.nextReminder;
    const parts: string[] = [];
    const goalsOpen = Today.openGoals.length;
    const goalsTotal = goalsOpen + Today.goalsDone;
    if (goalsTotal > 0) parts.push(tr.today.goalsCount(Today.goalsDone, goalsTotal));
    if (open > goalsOpen) parts.push(tr.today.pending(open - goalsOpen));
    if (next?.dueAt != null) parts.push(tr.today.next(dueLabel(next.dueAt).toLowerCase()));
    summary.textContent = parts.length ? parts.join(" · ") : tr.today.nothingPlanned;

    const f = Today.focus;
    const paused = isPaused(f);
    paintClock();
    const n = Today.blocksToday;
    caption.textContent =
      f.phase === "idle"
        ? n === 0 ? tr.today.focus : tr.today.blocksToday(n)
        : paused ? tr.today.paused : f.phase === "focus" ? tr.today.focus : tr.today.rest;
    caption.style.color = f.phase === "focus" ? FOCUS_COLOR : f.phase === "rest" ? REST_COLOR : "var(--dim-3)";

    // Buttons are rebuilt only when they change, or a click between mouse-down
    // and mouse-up would be swallowed.
    const key = `${f.phase}:${paused}`;
    if (key !== chipsKey) {
      chipsKey = key;
      clear(chips);
      if (f.phase === "idle") {
        chips.append(chip(tr.today.start, ICONS.play, FOCUS_COLOR, () => Today.startFocus()));
      } else {
        if (paused) chips.append(chip(tr.today.resume, ICONS.play, FOCUS_COLOR, () => Today.resume()));
        else if (f.phase === "focus") chips.append(chip(tr.today.pause, ICONS.pause, null, () => Today.pause()));
        else chips.append(chip(tr.today.skip, ICONS.forward, null, () => Today.stopFocus()));
        if (f.phase === "focus" || paused) chips.append(chip(null, ICONS.stop, null, () => Today.stopFocus()));
      }
    }
  }

  function syncList() {
    // Goals first, then the rest.
    const open = Today.openItems;
    const all: TodayItem[] = [...open.filter((i) => i.goal), ...open.filter((i) => !i.goal), ...Today.items.filter((i) => i.done)];
    clearDone.style.display = Today.items.some((i) => i.done) ? "" : "none";
    const key = all.map((i) => `${i.id}:${i.goal}:${i.done}:${i.dueAt}:${i.firedAt}:${i.text}`).join("|");
    if (key === rowsKey) return;
    rowsKey = key;
    clear(rows);
    if (all.length === 0) {
      rows.append(h("div", { class: "today-empty", text: tr.today.empty }));
      return;
    }
    for (const item of all) rows.append(todayRow(item));
  }

  function sync() {
    if (listOpen) syncList();
    else syncFace();
    Today.syncPill();
    ensureTicker();
  }

  return { el, sync, toggleList };
}

function todayRow(item: TodayItem): HTMLElement {
  const box = h("button", { class: item.done ? "today-check on" : "today-check", onclick: () => Today.toggleDone(item.id) });
  if (item.done) box.append(svg(ICONS.check, 7, { stroke: 3.4 }));
  const text = h("span", { class: item.done ? "today-text done" : "today-text", text: item.text });
  const row = h("div", { class: "today-row" }, box, text, h("div", { class: "grow" }));
  if (item.goal && !item.done) row.insertBefore(h("span", { class: "today-goal-tag", text: tr.today.goal }), row.querySelector(".grow"));
  if (item.dueAt != null && !item.done) {
    const due = h("span", { class: "today-due", text: dueLabel(item.dueAt) });
    if (item.firedAt != null) due.style.color = FOCUS_COLOR;
    row.append(due);
  }
  row.append(h("button", { class: "today-del", title: tr.today.remove, onclick: () => Today.remove(item.id) }, svg(ICONS.xmark, 8)));
  return row;
}

// ── Alert card (reminder due, focus block over, break over) ──────────────────

export function buildTodayAlert(): { el: HTMLElement; sync(): void } {
  const who = h("div", { class: "who-row" });
  const title = h("div", { class: "title today-alert-title" });
  const primary = h("button", { class: "btn primary", onclick: () => Today.respond("primary") }, h("span"));
  const secondary = h("button", { class: "btn secondary", onclick: () => Today.respond("secondary") }, h("span"));
  const row = h("div", { class: "actions" }, primary, secondary);
  const body = h("div", { class: "stack" }, who, title, row);
  body.style.padding = "4px 16px 4px 116px";
  const cardEl = h("div", { class: "card wash" }, body);
  const el = h("div", { class: "view" }, cardEl);

  return {
    el,
    sync() {
      const a = Today.currentAlert;
      if (!a) return;
      const wash = a.kind === "focusDone" ? "green" : a.kind === "restDone" ? "indigo" : "cyan";
      cardEl.style.setProperty("--wash", washRGBA(wash));
      clear(who);
      let label = "";
      if (a.kind === "reminder") {
        label = a.late ? tr.today.missed(dueLabel(a.dueAt)) : tr.today.reminder(dueLabel(a.dueAt));
      } else if (a.kind === "focusDone") {
        label = tr.today.focusDone(a.blocksToday);
      } else {
        label = tr.today.restDone;
      }
      who.append(dot(TODAY_COLOR, 8), h("span", { class: "n", text: tr.today.name }), h("span", { text: label }));
      title.textContent =
        a.kind === "reminder" ? a.text
        : a.kind === "focusDone" ? tr.today.focusDoneTitle
        : tr.today.restDoneTitle;
      (primary.firstChild as HTMLElement).textContent =
        a.kind === "focusDone" ? tr.today.restFive : a.kind === "restDone" ? tr.today.focus25 : tr.today.done;
      (secondary.firstChild as HTMLElement).textContent =
        a.kind === "focusDone" ? tr.today.later : a.kind === "restDone" ? tr.today.notNow : tr.today.snooze;
    },
  };
}

// ── Compact countdown ─────────────────────────────────────────────────────────

/**
 * A 2 px line along the bottom of the compact island that shrinks as the focus
 * block (amber) or break (green) runs out.
 */
export function buildFocusBar(): { el: HTMLElement; sync(compact: boolean, islandW: number): void } {
  const fill = h("i");
  const el = h("div", { id: "focus-bar" }, fill);
  let visible = false;
  let track = 0;

  function paint() {
    if (!visible) return;
    const f = Today.focus;
    fill.style.width = `${track * fraction(f)}px`;
    fill.style.background = f.phase === "focus" ? FOCUS_COLOR : REST_COLOR;
    fill.style.opacity = isPaused(f) ? "0.45" : "0.85";
  }
  tickers.add(paint);

  return {
    el,
    sync(compact, islandW) {
      visible = compact && Today.focus.phase !== "idle";
      el.style.opacity = visible ? "1" : "0";
      track = Math.max(0, islandW - 28);
      el.style.width = `${track}px`;
      paint();
      ensureTicker();
    },
  };
}

// ── Compact strip ─────────────────────────────────────────────────────────────

const STRIP_COLORS = { focus: FOCUS_COLOR, rest: REST_COLOR, goals: TODAY_COLOR, reminder: "#A78BFA" } as const;

/**
 * Text in the middle of the compact island (the empty "notch" of a PC): focus
 * clock, goals done and the next reminder, so they are in sight without opening
 * anything. Clicks go through it to the island.
 */
export function buildTodayStrip(): { el: HTMLElement; sync(compact: boolean, islandW: number, islandH: number): void } {
  const el = h("div", { id: "today-strip" });
  let visible = false;
  let key = "";

  function paint() {
    if (!visible) return;
    const parts = Today.compactParts();
    const k = parts.map((p) => `${p.kind}:${p.text}:${p.paused}`).join("|");
    if (k === key) return;
    key = k;
    clear(el);
    for (const p of parts) {
      const span = h("span", { class: `strip-part ${p.kind}`, style: `color:${STRIP_COLORS[p.kind]}` }, dot(STRIP_COLORS[p.kind], 4), h("b", { text: p.text }));
      if (p.paused) span.style.opacity = "0.55";
      el.append(span);
    }
  }
  tickers.add(paint);

  return {
    el,
    sync(compact, islandW, islandH) {
      visible = compact && Today.compactParts().length > 0;
      el.style.opacity = visible ? "1" : "0";
      el.style.left = "56px";
      el.style.width = `${Math.max(0, islandW - 56 - 66)}px`;
      el.style.top = `${islandH / 2 - 8}px`;
      key = "";
      paint();
      ensureTicker();
    },
  };
}
