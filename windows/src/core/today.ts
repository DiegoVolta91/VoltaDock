// "Hoy": a focus timer, quick to-dos and reminders that live in the island.
// Everything stays on this PC (localStorage); nothing is sent anywhere.
// Port of TodayStore.swift — keep the two in step.

import { parseQuickAdd } from "./quickadd";
import { tr } from "../i18n";
import { State } from "./state";

export interface TodayItem {
  id: string;
  text: string;
  /** Epoch ms; null = a plain to-do with no time. */
  dueAt: number | null;
  done: boolean;
  doneAt: number | null;
  createdAt: number;
  /** Set once the reminder has been shown, so it never fires twice. */
  firedAt: number | null;
}

export type FocusPhase = "idle" | "focus" | "rest";

export interface FocusSession {
  phase: FocusPhase;
  /** When the running phase ends; null while paused or idle. */
  endsAt: number | null;
  /** Ms left when paused. */
  pausedRemaining: number | null;
  /** Full length of the current phase, for the progress bar. */
  duration: number;
}

export type TodayAlert =
  | { kind: "reminder"; id: string; text: string; dueAt: number; late: boolean }
  | { kind: "focusDone"; blocksToday: number }
  | { kind: "restDone" };

/** What the island does for the store: show the alert card, react, close. */
export interface TodayHost {
  showAlert(): void;
  collapse(): void;
  emote(name: "wink" | "proud" | "happy"): void;
  sound(name: "question" | "finish" | "greet" | "work" | "yawn"): void;
}

export const FOCUS_MS = 25 * 60_000;
export const REST_MS = 5 * 60_000;
/** A phase that ended longer ago than this (PC asleep, app closed) closes quietly. */
const STALE_MS = 60 * 60_000;
/** A reminder shown more than this late is labelled as missed. */
const LATE_MS = 2 * 60_000;

const ITEMS_KEY = "voltadock.today.items";
const FOCUS_KEY = "voltadock.today.focus";
const BLOCKS_KEY = "voltadock.today.blocks";

const IDLE: FocusSession = { phase: "idle", endsAt: null, pausedRemaining: null, duration: 0 };

export function dayKey(ms: number): string {
  const d = new Date(ms);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function remaining(f: FocusSession, now = Date.now()): number {
  if (f.endsAt != null) return Math.max(0, f.endsAt - now);
  return f.pausedRemaining ?? 0;
}

export function isPaused(f: FocusSession): boolean {
  return f.phase !== "idle" && f.endsAt == null;
}

/** 1 → 0 as the phase runs out. */
export function fraction(f: FocusSession, now = Date.now()): number {
  if (f.duration <= 0) return 0;
  return Math.min(1, Math.max(0, remaining(f, now) / f.duration));
}

export function clock(ms: number): string {
  const s = Math.ceil(ms / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

/** "14:30", "Mañana 09:00", "jue 09:00" (in the current language). */
export function dueLabel(ms: number, now = Date.now()): string {
  const d = new Date(ms);
  const time = d.toLocaleTimeString(tr.tag, { hour: "2-digit", minute: "2-digit" });
  if (dayKey(ms) === dayKey(now)) return time;
  const tomorrow = new Date(now);
  tomorrow.setDate(tomorrow.getDate() + 1);
  if (dayKey(ms) === dayKey(tomorrow.getTime())) return `${tr.today.tomorrow} ${time}`;
  return `${d.toLocaleDateString(tr.tag, { weekday: "short" })} ${time}`;
}

function read<T>(key: string, fallback: T): T {
  try {
    // Builds before the rename stored these under "coucou.…": adopt them once.
    const legacy = key.replace(/^voltadock\./, "coucou.");
    const raw = localStorage.getItem(key) ?? localStorage.getItem(legacy);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function write(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* storage can be unavailable; the list just won't survive a restart */
  }
}

class TodayStore {
  items: TodayItem[] = [];
  focus: FocusSession = { ...IDLE };
  blocksByDay: Record<string, number> = {};
  currentAlert: TodayAlert | null = null;

  host: TodayHost | null = null;

  private pending: TodayAlert[] = [];
  private timer: number | null = null;
  private retryTimer: number | null = null;

  constructor() {
    this.items = read<TodayItem[]>(ITEMS_KEY, []);
    this.focus = { ...IDLE, ...read<Partial<FocusSession>>(FOCUS_KEY, {}) };
    this.blocksByDay = read<Record<string, number>>(BLOCKS_KEY, {});
    // Ticked items go away the day after; block counts are kept for two weeks.
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    this.items = this.items.filter((i) => !i.done || (i.doneAt ?? i.createdAt) >= today.getTime());
    const oldest = dayKey(today.getTime() - 14 * 86_400_000);
    for (const k of Object.keys(this.blocksByDay)) if (k < oldest) delete this.blocksByDay[k];
  }

  /** Called once at launch: catches up on what came due while the app was closed. */
  start(host: TodayHost) {
    this.host = host;
    // A timer that slept with the PC fires late; coming back to the screen is
    // another good moment to look.
    document.addEventListener("visibilitychange", () => this.check());
    window.addEventListener("focus", () => this.check());
    this.check();
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  get openItems(): TodayItem[] {
    return this.items
      .filter((i) => !i.done)
      .sort((a, b) => {
        if (a.dueAt != null && b.dueAt != null) return a.dueAt - b.dueAt;
        if (a.dueAt != null) return -1;
        if (b.dueAt != null) return 1;
        return a.createdAt - b.createdAt;
      });
  }

  get nextReminder(): TodayItem | null {
    return this.openItems.find((i) => i.dueAt != null && i.firedAt == null) ?? null;
  }

  get blocksToday(): number {
    return this.blocksByDay[dayKey(Date.now())] ?? 0;
  }

  // ── Items ──────────────────────────────────────────────────────────────────

  add(raw: string): TodayItem | null {
    const parsed = parseQuickAdd(raw, new Date(), { timer: tr.today.timerTitle, reminder: tr.today.reminderTitle });
    if (!parsed) return null;
    const item: TodayItem = {
      id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      text: parsed.title,
      dueAt: parsed.dueAt,
      done: false,
      doneAt: null,
      createdAt: Date.now(),
      firedAt: null,
    };
    this.items.push(item);
    this.commit();
    return item;
  }

  toggleDone(id: string) {
    const i = this.items.find((x) => x.id === id);
    if (!i) return;
    i.done = !i.done;
    i.doneAt = i.done ? Date.now() : null;
    this.commit();
  }

  remove(id: string) {
    this.items = this.items.filter((x) => x.id !== id);
    this.commit();
  }

  clearDone() {
    this.items = this.items.filter((x) => !x.done);
    this.commit();
  }

  snooze(id: string, minutes = 10) {
    const i = this.items.find((x) => x.id === id);
    if (!i) return;
    i.dueAt = Date.now() + minutes * 60_000;
    i.firedAt = null;
    i.done = false;
    this.commit();
  }

  // ── Focus ──────────────────────────────────────────────────────────────────

  startFocus() {
    this.begin("focus", FOCUS_MS);
  }

  startRest() {
    this.begin("rest", REST_MS);
  }

  pause() {
    const f = this.focus;
    if (f.phase === "idle" || f.endsAt == null) return;
    this.focus = { ...f, pausedRemaining: Math.max(0, f.endsAt - Date.now()), endsAt: null };
    this.commit();
  }

  resume() {
    const f = this.focus;
    if (!isPaused(f)) return;
    this.focus = { ...f, endsAt: Date.now() + (f.pausedRemaining ?? 0), pausedRemaining: null };
    this.commit();
  }

  stopFocus() {
    this.focus = { ...IDLE };
    this.commit();
  }

  private begin(phase: FocusPhase, length: number) {
    this.focus = { phase, endsAt: Date.now() + length, pausedRemaining: null, duration: length };
    this.host?.sound(phase === "focus" ? "work" : "yawn");
    this.commit();
  }

  // ── Alerts ─────────────────────────────────────────────────────────────────

  /** The buttons on the alert card. */
  respond(action: "primary" | "secondary") {
    const alert = this.currentAlert;
    if (!alert) return;
    this.currentAlert = null;
    State.isPinned = false;
    if (alert.kind === "reminder") {
      if (action === "primary") this.markDone(alert.id);
      else this.snooze(alert.id);
    } else if (action === "primary") {
      if (alert.kind === "focusDone") this.startRest();
      else this.startFocus();
    }
    // Starting a break or a block re-runs the clock, which may already have put
    // the next alert on screen.
    if (this.currentAlert) return;
    if (this.pending.length === 0) this.host?.collapse();
    else this.presentNext();
    State.notify();
  }

  /** The island moved to another view while an alert was up. */
  viewChanged() {
    const alert = this.currentAlert;
    if (!alert || State.view === "reminder") return;
    this.currentAlert = null;
    if (State.pendingApproval) {
      // Pushed aside by a permission request: show it again afterwards.
      this.pending.unshift(alert);
      this.scheduleRetry();
    } else {
      // The user moved on; the item stays in the list, unchecked.
      State.isPinned = false;
    }
  }

  private markDone(id: string) {
    const i = this.items.find((x) => x.id === id);
    if (!i || i.done) return;
    i.done = true;
    i.doneAt = Date.now();
    this.commit();
  }

  private presentNext() {
    if (this.currentAlert || this.pending.length === 0 || !this.host) return;
    // A permission request, another alert or the launch greeting is on screen:
    // wait for it.
    const greeting = State.mode === "expanded" && State.view === "greeting";
    if (State.isPinned || State.pendingApproval || greeting) {
      this.scheduleRetry();
      return;
    }
    const next = this.pending.shift()!;
    this.currentAlert = next;
    State.isPinned = true;
    if (next.kind === "reminder") {
      this.host.sound("question");
      this.host.emote("wink");
    } else if (next.kind === "focusDone") {
      this.host.sound("finish");
      this.host.emote("proud");
    } else {
      this.host.sound("greet");
      this.host.emote("happy");
    }
    this.host.showAlert();
  }

  private scheduleRetry() {
    if (this.retryTimer != null) return;
    this.retryTimer = window.setTimeout(() => {
      this.retryTimer = null;
      this.presentNext();
    }, 5000);
  }

  // ── Clock ──────────────────────────────────────────────────────────────────

  /**
   * Fires whatever is due, then arms one timer for the next event. No polling:
   * between events the store costs nothing.
   */
  check() {
    const now = Date.now();
    let changed = false;
    const f = this.focus;

    if (f.phase !== "idle" && f.endsAt != null && f.endsAt <= now) {
      const stale = now - f.endsAt > STALE_MS;
      if (f.phase === "focus") {
        const k = dayKey(f.endsAt);
        this.blocksByDay[k] = (this.blocksByDay[k] ?? 0) + 1;
      }
      const finished = f.phase;
      this.focus = { ...IDLE };
      changed = true;
      if (!stale) {
        this.pending.push(
          finished === "focus" ? { kind: "focusDone", blocksToday: this.blocksToday } : { kind: "restDone" },
        );
      }
    }

    for (const i of this.items) {
      if (i.done || i.firedAt != null || i.dueAt == null || i.dueAt > now) continue;
      i.firedAt = now;
      changed = true;
      this.pending.push({ kind: "reminder", id: i.id, text: i.text, dueAt: i.dueAt, late: now - i.dueAt > LATE_MS });
    }

    if (changed) this.save();
    this.syncPill();
    this.arm();
    this.presentNext();
    State.notify();
  }

  private arm() {
    if (this.timer != null) window.clearTimeout(this.timer);
    this.timer = null;
    const next = [this.focus.endsAt, this.nextReminder?.dueAt ?? null].filter((x): x is number => x != null);
    if (next.length === 0) return;
    // setTimeout overflows past ~24.8 days; wake up in time to re-arm.
    const delay = Math.min(Math.max(0, Math.min(...next) - Date.now()) + 50, 2 ** 31 - 1);
    this.timer = window.setTimeout(() => this.check(), delay);
  }

  /** Every mutation goes through here: persist, re-arm, refresh the pill. */
  private commit() {
    this.save();
    this.check();
  }

  /** The Hoy pill's mini Mochi works during a focus block and naps on a break. */
  syncPill() {
    const f = this.focus;
    const s = f.phase === "focus" ? (isPaused(f) ? "idle" : "working") : f.phase === "rest" ? "sleeping" : "idle";
    const t = State.tasks.find((x) => x.id === "integration_today");
    if (t && t.state !== s) State.updateTask("integration_today", s);
  }

  private save() {
    write(ITEMS_KEY, this.items);
    write(FOCUS_KEY, this.focus);
    write(BLOCKS_KEY, this.blocksByDay);
  }
}

export const Today = new TodayStore();
