// Entry point: boot the bridge, wire the island, start the greeting.

import "./style.css";
import { Bridge, IS_TAURI, onEvent } from "./core/bridge";
import { Sound } from "./core/sound";
import { State, type Settings } from "./core/state";
import { Island } from "./island/island";
import { registerHookHandlers } from "./island/hooks";
import { registerIntegrationHandlers, refreshConfigured } from "./island/integrations";
import { Today } from "./core/today";
import { setLanguage } from "./i18n";

/** Once at launch, only if the user asked for it; a version is announced once. */
async function lookForUpdate() {
  if (!State.settings.updateCheck || !IS_TAURI) return;
  await new Promise((r) => window.setTimeout(r, 20_000));
  if (!State.settings.updateCheck) return;
  const info = await Bridge.checkUpdate();
  if (!info || info.status !== "newer" || !info.url) return;
  const KEY = "coucou.update.seen";
  try {
    if (localStorage.getItem(KEY) === info.version) return;
    localStorage.setItem(KEY, info.version);
  } catch {
    /* announce anyway */
  }
  Today.announceUpdate(info.version, info.url);
}

async function main() {
  const root = document.getElementById("root");
  if (!root) return;

  void Sound.preload();

  const island = new Island(root);

  const boot = await Bridge.boot();
  if (boot) {
    State.settings = { ...State.settings, ...boot.settings };
  }
  // The island was built in the system language; redraw it if the setting says otherwise.
  if (setLanguage(State.settings.language)) island.relocalize();
  island.applySettings();
  State.loadIntegrationTasks();

  await onEvent<{ x: number; y: number }>("cursor", ({ x, y }) => island.onCursor(x, y));

  /** Pause has to reach Rust too, or the pollers keep calling out. */
  const setPaused = (on: boolean) => {
    if (State.paused === on) return;
    State.paused = on;
    void Bridge.setPaused(on);
  };

  await onEvent<string>("tray", (what) => {
    switch (what) {
      case "settings":
        setPaused(false);
        island.alert("settings");
        break;
      case "open":
        setPaused(false);
        island.alert(State.defaultView());
        break;
      case "focus":
        setPaused(false);
        Today.startFocus();
        island.reveal();
        break;
      case "pause":
        setPaused(!State.paused);
        if (State.paused) island.fsm.forceHidden();
        else island.reveal();
        break;
    }
  });

  await onEvent<null>("screen-changed", () => void Bridge.reposition());

  // "Borrar mis datos" in Ajustes: empty what this window keeps in memory too.
  await onEvent<null>("data-cleared", () => {
    try {
      for (const k of Object.keys(localStorage)) if (k.startsWith("coucou.")) localStorage.removeItem(k);
    } catch {
      /* storage can be unavailable */
    }
    Today.reset();
    State.sessions = [];
    State.chatHistory = [];
    State.notify();
  });

  // The settings window writes preferences; apply them here without a restart.
  await onEvent<Settings>("settings-changed", (s) => {
    State.settings = { ...State.settings, ...s };
    if (setLanguage(State.settings.language)) island.relocalize();
    island.applySettings();
    State.loadIntegrationTasks();
    void refreshConfigured();
  });

  registerHookHandlers(island);
  registerIntegrationHandlers(island);

  island.launch();
  island.startToday();
  void lookForUpdate();

  // In a plain browser there is no wake strip behind the cursor: make the whole
  // page wake the island so the visuals can be checked with `npm run dev`.
  if (!IS_TAURI) {
    document.addEventListener("click", () => Sound.resume(), { once: true });
  }
}

void main();
