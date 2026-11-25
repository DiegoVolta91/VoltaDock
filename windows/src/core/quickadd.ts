// Quick add for the "Hoy" card: turns a short line such as "en 10 min estirar",
// "mañana a las 9 dentista" or "at 5pm call Ana" into a title and an optional
// due time. No model involved, just a few patterns, so it works offline and
// never sends what you type anywhere. Mirror of QuickAdd in TodayStore.swift:
// keep the two in step.

/** How a reminder comes back. 0 = Sunday, as in Date#getDay. */
export type Repeat =
  | { kind: "interval"; everyMs: number }
  | { kind: "daily" }
  | { kind: "weekdays" }
  | { kind: "weekly"; dow: number };

export interface QuickAdd {
  title: string;
  /** Epoch ms; null = a plain to-do with no time. */
  dueAt: number | null;
  /** True for "in 10 min" style input, which is shown as a timer. */
  relative: boolean;
  /** "every day at 9", "cada lunes", "cada 2 horas"; null = fires once. */
  repeat: Repeat | null;
}

const UNIT_MS: [RegExp, number][] = [
  [/^(h|hr|hrs|hour|hours|hora|horas)$/, 3_600_000],
  [/^(m|min|mins|minute|minutes|minuto|minutos)$/, 60_000],
];

// Order matters: a time written with "at"/"a las" wins over the relative form,
// so "a las 9h" is nine o'clock, not nine hours from now.
const AT_TIME = /(?:^|\s)(?:at|a\s+las|a\s+la|@)\s*(\d{1,2})(?:[:.h](\d{2})|h)?\s*(am|pm)?(?=\s|$|[,.!?])/i;
const RELATIVE = /(?:^|\s)(?:(?:in|en|dentro\s+de)\s+)?(\d{1,3})\s*(h|hr|hrs|hours?|horas?|m|mins?|minutes?|minutos?)(?=\s|$|[,.!?])/i;
const BARE_TIME = /(?:^|\s)(\d{1,2})(?::(\d{2})\s*(am|pm)?|\s*(am|pm))(?=\s|$|[,.!?])/i;
const DAY_WORD = /(?:^|\s)(tomorrow|mañana|manana|today|hoy)(?=\s|$|[,.!?])/i;
const DAY_NAMES: [RegExp, number][] = [
  [/^(domingo|sunday)$/, 0],
  [/^(lunes|monday)$/, 1],
  [/^(martes|tuesday)$/, 2],
  [/^(mi[eé]rcoles|wednesday)$/, 3],
  [/^(jueves|thursday)$/, 4],
  [/^(viernes|friday)$/, 5],
  [/^(s[aá]bado|saturday)$/, 6],
];
const DAY_NAME = "lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo|monday|tuesday|wednesday|thursday|friday|saturday|sunday";
const EVERY_DAY = /(?:^|\s)(?:cada\s+d[ií]a|todos\s+los\s+d[ií]as|diari[oa]s?|every\s*day|daily)(?=\s|$|[,.!?])/i;
const WEEKDAYS = /(?:^|\s)(?:entre\s+semana|de\s+lunes\s+a\s+viernes|(?:on\s+)?weekdays?|every\s+weekday)(?=\s|$|[,.!?])/i;
const EVERY_DOW = new RegExp(`(?:^|\\s)(?:cada|todos\\s+los|every)\\s+(${DAY_NAME})(?=\\s|$|[,.!?])`, "i");
const EVERY_INTERVAL = /(?:^|\s)(?:cada|every)\s+(?:(\d{1,3})\s*)?(h|hr|hrs|hours?|horas?|m|mins?|minutes?|minutos?)(?=\s|$|[,.!?])/i;
const LEAD_IN = /^(?:remind\s+me\s+(?:to\s+)?|reminder:?\s*|recu[eé]rdame\s+(?:que\s+|de\s+)?|recordatorio:?\s*|timer:?\s*|temporizador(?:\s+de)?:?\s*)/i;

function toHour(h: number, m: number, ampm: string | undefined): [number, number] | null {
  let hour = h;
  const mer = ampm?.toLowerCase();
  if (mer === "pm" && hour < 12) hour += 12;
  if (mer === "am" && hour === 12) hour = 0;
  if (hour > 23 || m > 59) return null;
  return [hour, m];
}

/**
 * The first moment at hh:mm that is after `after` and fits the rule. Interval
 * rules have no clock: they step forward from `after`.
 */
function occurrence(rep: Repeat, hh: number, mm: number, after: number): number {
  if (rep.kind === "interval") return after + rep.everyMs;
  const d = new Date(after);
  d.setHours(hh, mm, 0, 0);
  for (let i = 0; i < 9; i++) {
    const day = d.getDay();
    const fits =
      rep.kind === "daily" ||
      (rep.kind === "weekdays" && day >= 1 && day <= 5) ||
      (rep.kind === "weekly" && day === rep.dow);
    if (fits && d.getTime() > after) return d.getTime();
    d.setDate(d.getDate() + 1);
    d.setHours(hh, mm, 0, 0);
  }
  return d.getTime();
}

/** Where a repeating reminder goes after it fired: same time of day, next fitting day. */
export function nextDue(rep: Repeat, prevDue: number, now: number = Date.now()): number {
  if (rep.kind === "interval") {
    const steps = Math.max(1, Math.floor((now - prevDue) / rep.everyMs) + 1);
    return prevDue + steps * rep.everyMs;
  }
  const p = new Date(prevDue);
  return occurrence(rep, p.getHours(), p.getMinutes(), now);
}

export function parseQuickAdd(
  raw: string,
  now: Date = new Date(),
  fallback = { timer: "Temporizador", reminder: "Recordatorio" },
): QuickAdd | null {
  let text = ` ${raw.trim()} `;
  if (!text.trim()) return null;

  let due: Date | null = null;
  let relative = false;
  let clock: [number, number] | null = null;
  let dayOffset: number | null = null;

  const cut = (m: RegExpMatchArray) => {
    text = text.slice(0, m.index!) + " " + text.slice(m.index! + m[0].length);
  };

  // A repeat is read first and cut out, so "cada 10 min" is not mistaken for a
  // one-off "in 10 min".
  let repeat: Repeat | null = null;
  const everyInt = text.match(EVERY_INTERVAL);
  const everyDow = text.match(EVERY_DOW);
  const weekdays = text.match(WEEKDAYS);
  const everyDay = text.match(EVERY_DAY);
  if (everyInt) {
    const unit = UNIT_MS.find(([re]) => re.test(everyInt[2].toLowerCase()));
    const n = everyInt[1] ? Number(everyInt[1]) : 1;
    if (unit && n > 0) {
      repeat = { kind: "interval", everyMs: n * unit[1] };
      cut(everyInt);
    }
  } else if (everyDow) {
    const w = everyDow[1].toLowerCase();
    const dow = DAY_NAMES.find(([re]) => re.test(w));
    if (dow) {
      repeat = { kind: "weekly", dow: dow[1] };
      cut(everyDow);
    }
  } else if (weekdays) {
    repeat = { kind: "weekdays" };
    cut(weekdays);
  } else if (everyDay) {
    repeat = { kind: "daily" };
    cut(everyDay);
  }

  const at = text.match(AT_TIME);
  if (at) {
    clock = toHour(Number(at[1]), Number(at[2] ?? 0), at[3]);
    if (clock) cut(at);
  }

  if (!clock) {
    const rel = text.match(RELATIVE);
    if (rel) {
      const unit = UNIT_MS.find(([re]) => re.test(rel[2].toLowerCase()));
      const n = Number(rel[1]);
      if (unit && n > 0) {
        due = new Date(now.getTime() + n * unit[1]);
        relative = true;
        cut(rel);
      }
    }
  }

  if (!clock && !relative) {
    const bare = text.match(BARE_TIME);
    if (bare) {
      clock = toHour(Number(bare[1]), Number(bare[2] ?? 0), bare[3] ?? bare[4]);
      if (clock) cut(bare);
    }
  }

  if (!relative && !repeat) {
    const day = text.match(DAY_WORD);
    if (day) {
      const w = day[1].toLowerCase();
      dayOffset = w === "today" || w === "hoy" ? 0 : 1;
      cut(day);
    }
  }

  if (repeat) {
    const [hh, mm] = clock ?? [9, 0];
    due = new Date(occurrence(repeat, hh, mm, now.getTime()));
  } else if (!relative && (clock || dayOffset === 1)) {
    const [hh, mm] = clock ?? [9, 0];
    const d = new Date(now);
    d.setHours(hh, mm, 0, 0);
    if (dayOffset) d.setDate(d.getDate() + dayOffset);
    // "at 9" when nine has already gone means tomorrow morning.
    else if (dayOffset === null && d.getTime() <= now.getTime()) d.setDate(d.getDate() + 1);
    due = d;
  }

  let title = text.replace(/\s+/g, " ").trim().replace(LEAD_IN, "");
  title = title.replace(/^[\s,.:;\-–]+|[\s,.:;\-–]+$/g, "").trim();
  if (!title) title = relative ? fallback.timer : fallback.reminder;
  title = title.charAt(0).toUpperCase() + title.slice(1);

  return { title, dueAt: due ? due.getTime() : null, relative, repeat };
}
