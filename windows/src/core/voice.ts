// Spoken announcements ("Claude terminó", "necesita permiso") with the voice that
// already ships with Windows, through the browser's speech synthesis. Nothing is
// recorded and nothing is sent anywhere. Off by default (Ajustes → Voz).
// The Mac twin is Voice.swift (AVSpeechSynthesizer): keep the two in step.

import { State } from "./state";
import { tr } from "../i18n";

let lastText = "";
let lastAt = 0;

function pickVoice(lang: string): SpeechSynthesisVoice | null {
  const voices = window.speechSynthesis.getVoices();
  return voices.find((v) => v.lang.toLowerCase().startsWith(lang) && v.localService) ??
    voices.find((v) => v.lang.toLowerCase().startsWith(lang)) ?? null;
}

export const Voice = {
  /** Speaks `text` if the user turned voice on; the same phrase is not repeated within 4 s. */
  say(text: string) {
    if (!State.settings.voiceEnabled || State.paused || !text) return;
    if (typeof window === "undefined" || !("speechSynthesis" in window)) return;
    const now = performance.now();
    if (text === lastText && now - lastAt < 4000) return;
    lastText = text;
    lastAt = now;
    try {
      const u = new SpeechSynthesisUtterance(text);
      u.lang = tr.tag;
      const v = pickVoice(tr.tag);
      if (v) u.voice = v;
      u.rate = 1.05;
      u.volume = Math.min(1, Math.max(0.3, State.settings.soundVolume * 5));
      // A new phrase replaces whatever is still being said.
      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(u);
    } catch {
      /* no voices installed: stay quiet */
    }
  },
};
