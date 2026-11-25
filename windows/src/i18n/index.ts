// Interface language. `tr` is a live binding: modules that import it always see
// the current locale, so code reads `tr.approval.allow` at render time.
//
// Spanish is the default. "system" follows the Windows display language (WebView2 reports it as
// navigator.language): Spanish when it is Spanish, English otherwise. Rust
// resolves the same preference on its side for the tray and its own messages
// (src-tauri/src/i18n.rs).

import { en } from "./en";
import { es, type Messages } from "./es";

export type Language = "system" | "es" | "en";
export type Locale = "es" | "en";
export type { Messages };

const LOCALES: Record<Locale, Messages> = { es, en };

/** Names shown in the language picker, each in its own language. */
export const LANGUAGE_NAMES: Record<Locale, string> = { es: "Español", en: "English" };

export function systemLocale(): Locale {
  const langs = navigator.languages?.length ? navigator.languages : [navigator.language];
  return (langs[0] ?? "").toLowerCase().startsWith("es") ? "es" : "en";
}

export function resolveLanguage(pref: string | undefined): Locale {
  return pref === "es" || pref === "en" ? pref : systemLocale();
}

// Spanish until the stored setting is read, which is also the default.
let current: Locale = "es";
export let tr: Messages = LOCALES[current];
document.documentElement.lang = current;

/** Applies a preference; returns true when the visible language changed. */
export function setLanguage(pref: string | undefined): boolean {
  const next = resolveLanguage(pref);
  if (next === current) return false;
  current = next;
  tr = LOCALES[next];
  document.documentElement.lang = next;
  return true;
}

export function currentLocale(): Locale {
  return current;
}
