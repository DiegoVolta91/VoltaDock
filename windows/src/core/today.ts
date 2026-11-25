// "Hoy": a focus timer, quick to-dos and reminders that live in the island.
// Everything stays on this PC (localStorage); nothing is sent anywhere.
// Port of TodayStore.swift — keep the two in step.

import { nextDue, parseQuickAdd, type Repeat } from "./quickadd";
import { Voice } from "./voice";
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
  /** A reminder that comes back ("cada lunes a las 9"); it never ends up done. */
  repeat?: Repeat | null;
}

/** A small daily routine with a streak ("beber agua"). */
export interface Habit {
  id: string;
  name: string;
  createdAt: number;
  /** Days it was done, as "YYYY-MM-DD"; only the last 120 are kept. */
  days: string[];
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
  | { kind: "restDone" }
  | { kind: "update"; version: string; url: string };

/** What the island does for the store: show the alert card, react, close. */
export interface TodayHost {
  showAlert(): void;
  collapse(): void;
  emote(name: "wink" | "proud" | "happy" | "cheer" | "worried"): void;
  /** The little green tick over Volt: "done, it worked". */
  confirm(): void;
  /** Opens a link (the new release page). */
  openUrl(url: string): void;
  sound(name: "question" | "finish" | "greet" | "work" | "yawn"): void;
}

export const FOCUS_MS = 25 * 60_000;
export const REST_MS = 5 * 60_000;
/** A phase that ended longer ago than this (PC asleep, app closed) closes quietly. */
const STALE_MS = 60 * 60_000;
/** A reminder shown more than this late is labelled as missed. */
const LATE_MS = 2 * 60_000;

const ITEMS_KEY = "coucou.today.items";
const FOCUS_KEY = "coucou.today.focus";
const BLOCKS_KEY = "coucou.today.blocks";
const HABITS_KEY = "coucou.today.habits";
const KEEP_DAYS = 120;

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
    const raw = localStorage.getItem(key);
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
  habits: Habit[] = [];
  currentAlert: TodayAlert | null = null;

  host: TodayHost | null = null;

  private pending: TodayAlert[] = [];
  private timer: number | null = null;
  private retryTimer: number | null = null;

  constructor() {
    this.items = read<TodayItem[]>(ITEMS_KEY, []);
    this.focus = { ...IDLE, ...read<Partial<FocusSession>>(FOCUS_KEY, {}) };
    this.blocksByDay = read<Record<string, number>>(BLOCKS_KEY, {});
    this.habits = read<Habit[]>(HABITS_KEY, []);
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

  /** The quick-add line: "hábito beber agua" starts a habit, anything else is a to-do. */
  addLine(raw: string): { kind: "item"; item: TodayItem } | { kind: "habit"; habit: Habit } | null {
    const m = raw.trim().match(/^(?:h[áa]bito|habit)s?:?\s+(.+)$/i);
    if (m) {
      const habit = this.addHabit(m[1]);
      return habit ? { kind: "habit", habit } : null;
    }
    const item = this.add(raw);
    return item ? { kind: "item", item } : null;
  }

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
      repeat: parsed.repeat,
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
    if (i.done) this.host?.confirm();
    this.commit();
  }

  // ── Habits ─────────────────────────────────────────────────────────────────

  addHabit(raw: string): Habit | null {
    const name = raw.trim().replace(/\s+/g, " ");
    if (!name) return null;
    const title = name.charAt(0).toUpperCase() + name.slice(1);
    const habit: Habit = { id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`, name: title, createdAt: Date.now(), days: [] };
    this.habits.push(habit);
    this.commit();
    return habit;
  }

  removeHabit(id: string) {
    this.habits = this.habits.filter((h) => h.id !== id);
    this.commit();
  }

  habitDoneToday(h: Habit): boolean {
    return h.days.includes(dayKey(Date.now()));
  }

  get habitsDoneToday(): number {
    return this.habits.filter((h) => this.habitDoneToday(h)).length;
  }

  /**
   * Consecutive days up to today. A day not yet ticked does not break the run
   * until it is over, so the streak survives until midnight.
   */
  streak(h: Habit): number {
    const done = new Set(h.days);
    const d = new Date();
    d.setHours(12, 0, 0, 0);
    if (!done.has(dayKey(d.getTime()))) d.setDate(d.getDate() - 1);
    let n = 0;
    while (done.has(dayKey(d.getTime()))) {
      n++;
      d.setDate(d.getDate() - 1);
    }
    return n;
  }

  toggleHabit(id: string) {
    const h = this.habits.find((x) => x.id === id);
    if (!h) return;
    const key = dayKey(Date.now());
    if (h.days.includes(key)) {
      h.days = h.days.filter((k) => k !== key);
      this.commit();
      return;
    }
    h.days.push(key);
    h.days.sort();
    if (h.days.length > KEEP_DAYS) h.days = h.days.slice(-KEEP_DAYS);
    this.commit();
    // The whole routine ticked off: a bigger celebration than a single tick.
    if (this.habitsDoneToday === this.habits.length) {
      this.host?.emote("cheer");
      this.host?.sound("finish");
    } else {
      this.host?.confirm();
    }
  }

  /** "Borrar mis datos": the lists are emptied, the preferences stay. */
  reset() {
    this.items = [];
    this.habits = [];
    this.focus = { ...IDLE };
    this.blocksByDay = {};
    this.currentAlert = null;
    this.pending = [];
    State.isPinned = false;
    this.commit();
  }

  /** A newer release exists: shown once as a card, and not again for the same version. */
  announceUpdate(version: string, url: string) {
    this.pending.push({ kind: "update", version, url });
    this.presentNext();
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
      const item = this.items.find((x) => x.id === alert.id);
      if (action === "primary") {
        // A repeating reminder has already moved on to its next time.
        if (!item?.repeat) this.markDone(alert.id);
        else this.host?.confirm();
      } else if (item?.repeat) {
        // Snoozing one occurrence must not push the whole series back.
        this.items.push({
          id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
          text: alert.text, dueAt: Date.now() + 10 * 60_000, done: false, doneAt: null,
          createdAt: Date.now(), firedAt: null, repeat: null,
        });
        this.commit();
      } else {
        this.snooze(alert.id);
      }
    } else if (alert.kind === "update") {
      if (action === "primary") this.host?.openUrl(alert.url);
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
      this.host.emote(next.late ? "worried" : "wink");
      Voice.say(tr.voice.reminder(next.text));
    } else if (next.kind === "update") {
      this.host.sound("greet");
      this.host.emote("happy");
    } else if (next.kind === "focusDone") {
      this.host.sound("finish");
      this.host.emote("cheer");
      Voice.say(tr.voice.focusDone);
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
      const dueAt = i.dueAt;
      changed = true;
      // A repeating reminder is re-armed at once for its next time, so a PC that
      // slept through three Mondays shows one card, not three.
      if (i.repeat) {
        i.dueAt = nextDue(i.repeat, dueAt, now);
        i.firedAt = null;
      } else {
        i.firedAt = now;
      }
      this.pending.push({ kind: "reminder", id: i.id, text: i.text, dueAt, late: now - dueAt > LATE_MS });
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
    write(HABITS_KEY, this.habits);
  }
}

export const Today = new TodayStore();
