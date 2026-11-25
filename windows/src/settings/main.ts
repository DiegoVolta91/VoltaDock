// Settings window — the place where anything that writes to disk is confirmed.
// Stage 2 covers the Claude Code hooks and the general preferences; API keys and
// integrations land here too in a later stage.

import "./settings.css";
import { Bridge, onEvent, type HookStatus } from "../core/bridge";
import { DEFAULT_SETTINGS, type Settings } from "../core/state";
import { h, clear } from "../views/dom";
import { LANGUAGE_NAMES, setLanguage, tr, type Language, type Messages } from "../i18n";

let settings: Settings = { ...DEFAULT_SETTINGS };
let version = "";

const root = document.getElementById("settings-root")!;

async function save() {
  await Bridge.saveSettings(settings);
}

// ── Reusable bits ─────────────────────────────────────────────────────────────

function toggle(on: boolean, onChange: (v: boolean) => void): HTMLElement {
  const el = h("button", { class: on ? "switch on" : "switch", "aria-pressed": on });
  el.addEventListener("click", () => {
    const next = !el.classList.contains("on");
    el.classList.toggle("on", next);
    onChange(next);
  });
  return el;
}

function statusDot(ok: boolean): HTMLElement {
  return h("i", { class: "dot", style: `background:${ok ? "#22c55e" : "#f4505e"}` });
}

function renderDiff(text: string): HTMLElement {
  const box = h("div", { class: "diff" });
  for (const line of text.split("\n")) {
    const cls = line.startsWith("+") ? "add" : line.startsWith("-") ? "del" : "ctx";
    box.append(h("div", { class: cls, text: line }));
  }
  return box;
}

// ── Claude Code section ───────────────────────────────────────────────────────

function claudeSection(status: HookStatus): HTMLElement {
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h(
    "section",
    {},
    h("h2", {}, statusDot(status.installed), h("span", { text: "Claude Code" })),
    body,
  );

  const rebuild = async () => {
    const fresh = await Bridge.hooksStatus();
    if (fresh) Object.assign(status, fresh);
    clear(body);
    draw();
    const head = section.querySelector("h2")!;
    clear(head);
    head.append(statusDot(status.installed), h("span", { text: "Claude Code" }));
  };

  function draw() {
    body.append(
      h("div", {
        class: "hint",
        text: status.installed
          ? tr.settings.claude.connected
          : tr.settings.claude.notConnected,
      }),
      h("div", { class: "row" },
        h("label", { text: "settings.json" }),
        h("span", { class: "path", text: status.settingsPath }),
      ),
      h("div", { class: "row" },
        h("label", { text: "Relay" }),
        h("span", { class: "path", text: status.hookPath }),
        statusDot(status.hookReady),
      ),
    );

    if (!status.hookReady) {
      body.append(h("div", {
        class: "notice warn",
        text: tr.settings.claude.hookMissing,
      }));
    }

    const actions = h("div", { class: "row" });
    const install = h("button", {
      class: "primary",
      text: status.installed ? tr.settings.claude.reinstall : tr.settings.claude.install,
      onclick: () => showPreview(true),
    });
    // Writing hook commands that point at a relay which isn't there would give
    // every Claude Code session a broken hook and nothing to show for it.
    if (!status.hookReady) {
      install.disabled = true;
      install.title = tr.settings.claude.relayMissing;
    }
    actions.append(install);
    if (status.installed) {
      actions.append(h("button", {
        class: "danger",
        text: tr.settings.claude.uninstall,
        onclick: () => showPreview(false),
      }));
    }
    body.append(actions);
  }

  async function showPreview(install: boolean) {
    let preview;
    try {
      preview = await Bridge.hooksPreview(install);
    } catch (err) {
      // An unreadable or invalid settings.json stops here rather than being
      // treated as empty and written over.
      clear(body);
      body.append(
        h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
        h("div", { class: "row" }, h("button", {
          text: tr.common.back,
          onclick: () => { clear(body); draw(); },
        })),
      );
      return;
    }
    if (!preview) return;
    clear(body);
    body.append(
      h("div", {
        class: "hint",
        text: install
          ? tr.settings.claude.previewInstall
          : tr.settings.claude.previewUninstall,
      }),
      renderDiff(preview.diff),
      h("div", { class: "row" },
        h("span", { class: "path", text: tr.settings.claude.backup(preview.backup) }),
      ),
    );
    const confirm = h("button", {
      class: install ? "primary" : "danger",
      text: install ? tr.settings.claude.confirmInstall : tr.settings.claude.confirmUninstall,
    });
    confirm.addEventListener("click", async () => {
      confirm.disabled = true;
      try {
        const backup = await Bridge.hooksApply(install, preview.fingerprint);
        clear(body);
        body.append(h("div", {
          class: "notice ok",
          text: tr.settings.claude.done(backup),
        }));
        window.setTimeout(() => void rebuild(), 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(h("div", { class: "notice err", text: tr.settings.claude.writeFailed(String(err)) }));
      }
    });
    body.append(h("div", { class: "row" }, confirm, h("button", {
      text: tr.common.cancel,
      onclick: () => { clear(body); draw(); },
    })));
  }

  draw();
  return section;
}

// ── Claude API section ────────────────────────────────────────────────────────

const MODELS: [string, string][] = [
  ["claude-opus-5", "Claude Opus 5"],
  ["claude-sonnet-5", "Claude Sonnet 5"],
  ["claude-haiku-4-5", "Claude Haiku 4.5"],
];

function apiSection(hasKey: boolean): HTMLElement {
  const dot = statusDot(hasKey);
  const state = h("span", { class: "hint", text: hasKey ? tr.settings.api.keySaved : tr.settings.api.noKey });

  const field = h("input", {
    type: "password",
    placeholder: hasKey ? `••••••••••••  ${tr.common.stored}` : "sk-ant-...",
    style: "flex:1 1 auto;min-width:0",
    autocomplete: "off",
    spellcheck: "false",
  }) as HTMLInputElement;

  const saveBtn = h("button", { class: "primary", text: tr.settings.api.saveKey });
  const clearBtn = h("button", { class: "danger", text: tr.settings.api.remove });
  const feedback = h("div", {});

  async function refresh() {
    const present = (await Bridge.secretPresent("anthropic-api-key")) ?? false;
    dot.style.background = present ? "#22c55e" : "#f4505e";
    state.textContent = present
      ? tr.settings.api.keySaved
      : tr.settings.api.noKey;
    field.placeholder = present ? `••••••••••••  ${tr.common.stored}` : "sk-ant-...";
    clearBtn.style.display = present ? "" : "none";
  }

  saveBtn.addEventListener("click", async () => {
    const value = field.value.trim();
    if (!value) return;
    clear(feedback);
    try {
      await Bridge.secretSet("anthropic-api-key", value);
      field.value = "";
      feedback.append(h("div", { class: "notice ok", text: tr.settings.api.saved }));
      await refresh();
    } catch (err) {
      feedback.append(h("div", { class: "notice err", text: tr.settings.api.saveFailed(String(err)) }));
    }
  });

  clearBtn.addEventListener("click", async () => {
    clear(feedback);
    try {
      await Bridge.secretClear("anthropic-api-key");
      feedback.append(h("div", { class: "notice ok", text: tr.settings.api.removed }));
      await refresh();
    } catch (err) {
      feedback.append(h("div", { class: "notice err", text: tr.settings.api.removeFailed(String(err)) }));
    }
  });

  const model = h("select", {}) as HTMLSelectElement;
  for (const [id, label] of MODELS) model.append(h("option", { value: id, text: label }));
  if (!MODELS.some(([id]) => id === settings.model)) {
    model.append(h("option", { value: settings.model, text: settings.model }));
  }
  model.value = settings.model;
  model.addEventListener("change", () => {
    settings.model = model.value;
    void save();
  });

  clearBtn.style.display = hasKey ? "" : "none";

  return h(
    "section",
    {},
    h("h2", {}, dot, h("span", { text: "Claude" })),
    state,
    h("div", { class: "row" }, h("label", { text: tr.settings.api.apiKey }), field, saveBtn, clearBtn),
    h("div", { class: "row" }, h("label", { text: tr.settings.api.model }), model),
    feedback,
  );
}

// ── Integrations section ──────────────────────────────────────────────────────

/** Field labels, looked up in `tr.settings.integrations` when drawn. */
type FieldLabel = keyof Omit<Messages["settings"]["integrations"], "title" | "note">;

interface IntegrationDef {
  id: string;
  name: string;
  color: string;
  /** Credential Manager keys, in the order they are shown. */
  fields: { key: string; label: FieldLabel; placeholder: string; secret: boolean }[];
  /** Shown instead of key fields for integrations that need none. */
  note?: string;
}

const INTEGRATIONS: IntegrationDef[] = [
  { id: "integration_stripe", name: "Stripe", color: "#0570DE",
    fields: [{ key: "stripe-api-key", label: "secretKey", placeholder: "sk_live_…", secret: true }] },
  { id: "integration_github", name: "GitHub", color: "#F4505E",
    fields: [{ key: "github-token", label: "token", placeholder: "ghp_…", secret: true }] },
  { id: "integration_vercel", name: "Vercel", color: "#7C5CFF",
    fields: [{ key: "vercel-token", label: "token", placeholder: "…", secret: true }] },
  { id: "integration_n8n", name: "n8n", color: "#F29B38",
    fields: [
      { key: "n8n-url", label: "instanceUrl", placeholder: "https://n8n.example.com", secret: false },
      { key: "n8n-api-key", label: "apiKey", placeholder: "…", secret: true },
    ] },
  { id: "integration_resend", name: "Resend", color: "#22C55E",
    fields: [{ key: "resend-api-key", label: "apiKey", placeholder: "re_…", secret: true }] },
  { id: "integration_notion", name: "Notion", color: "#8C8C8C",
    fields: [{ key: "notion-api-key", label: "integrationToken", placeholder: "ntn_…", secret: true }] },
  { id: "integration_calcom", name: "Cal.com", color: "#C9956A",
    fields: [{ key: "calcom-api-key", label: "apiKey", placeholder: "cal_…", secret: true }] },
  // Local only: nothing to configure, it just needs a slot.
  { id: "integration_today", color: "#2DD4BF", fields: [],
    get name() { return tr.today.name; },
    get note() { return tr.today.settingsNote; } },
];

const MAX_ACTIVE = 4;

function integrationsSection(present: Record<string, boolean>): HTMLElement {
  const note = h("div", { class: "hint" });
  const list = h("div", { style: "display:flex;flex-direction:column;gap:14px" });

  function updateNote() {
    const used = settings.activeIntegrations.length;
    note.textContent = tr.settings.integrations.note(used, MAX_ACTIVE);
  }

  for (const def of INTEGRATIONS) {
    const active = settings.activeIntegrations.includes(def.id);
    const sw = h("button", { class: active ? "switch on" : "switch" });
    sw.addEventListener("click", () => {
      const on = settings.activeIntegrations.includes(def.id);
      if (on) {
        settings.activeIntegrations = settings.activeIntegrations.filter((x) => x !== def.id);
      } else {
        if (settings.activeIntegrations.length >= MAX_ACTIVE) return;
        settings.activeIntegrations = [...settings.activeIntegrations, def.id];
      }
      sw.classList.toggle("on", !on);
      updateNote();
      void save();
    });

    const rows = h("div", { style: "display:flex;flex-direction:column;gap:6px;flex:1 1 auto;min-width:0" });
    for (const field of def.fields) {
      const input = h("input", {
        type: field.secret ? "password" : "text",
        placeholder: present[field.key] ? `••••••••  ${tr.common.stored}` : field.placeholder,
        autocomplete: "off",
        spellcheck: "false",
        style: "flex:1 1 auto;min-width:0",
      }) as HTMLInputElement;
      const saveBtn = h("button", { text: tr.common.save });
      const dotEl = statusDot(present[field.key] ?? false);
      saveBtn.addEventListener("click", async () => {
        const value = input.value.trim();
        try {
          await Bridge.secretSet(field.key, value);
          present[field.key] = value.length > 0;
          input.value = "";
          input.placeholder = value ? `••••••••  ${tr.common.stored}` : field.placeholder;
          dotEl.style.background = value ? "#22c55e" : "#f4505e";
        } catch {
          dotEl.style.background = "#f5a524";
        }
      });
      rows.append(
        h("div", { class: "row" },
          h("label", { style: "min-width:104px", text: tr.settings.integrations[field.label] }),
          input, saveBtn, dotEl,
        ),
      );
    }

    if (def.note) rows.append(h("div", { class: "hint", style: "padding-top:5px", text: def.note }));

    list.append(
      h("div", { style: "display:flex;gap:12px;align-items:flex-start" },
        h("div", { style: "display:flex;align-items:center;gap:8px;min-width:132px;padding-top:4px" },
          sw,
          h("i", { class: "dot", style: `background:${def.color}` }),
          h("span", { style: "font-size:12.5px", text: def.name }),
        ),
        rows,
      ),
    );
  }

  updateNote();
  return h("section", {}, h("h2", {}, h("span", { text: tr.settings.integrations.title })), note, list);
}

// ── General section ───────────────────────────────────────────────────────────

function generalSection(): HTMLElement {
  const volume = h("input", {
    type: "range", min: "0", max: "0.2", step: "0.005",
    value: String(settings.soundVolume),
  }) as HTMLInputElement;
  volume.addEventListener("input", () => {
    settings.soundVolume = Number(volume.value);
    void save();
  });

  const autoClose = h("input", {
    type: "number", min: "5", max: "120", step: "1",
    value: String(Math.round(settings.autoCloseInterval)),
    style: "width:72px",
  }) as HTMLInputElement;
  autoClose.addEventListener("change", () => {
    settings.autoCloseInterval = Math.max(5, Math.min(120, Number(autoClose.value) || 15));
    autoClose.value = String(settings.autoCloseInterval);
    void save();
  });

  const projectsRoot = h("input", {
    type: "text",
    value: settings.projectsRoot ?? "",
    placeholder: tr.settings.general.projectsRootAuto,
    style: "width:240px",
  }) as HTMLInputElement;
  projectsRoot.addEventListener("change", () => {
    settings.projectsRoot = projectsRoot.value.trim();
    void save();
  });

  const language = h("select", {}) as HTMLSelectElement;
  language.append(
    h("option", { value: "es", text: LANGUAGE_NAMES.es }),
    h("option", { value: "en", text: LANGUAGE_NAMES.en }),
    h("option", { value: "system", text: tr.settings.general.languageSystem }),
  );
  language.value = settings.language ?? "es";
  language.addEventListener("change", () => {
    settings.language = language.value as Language;
    void save();
    // Redraw this window at once; the island follows through settings-changed.
    if (setLanguage(settings.language)) void refreshLoaded().then(render);
  });

  const screen = h("select", {}) as HTMLSelectElement;
  screen.append(
    h("option", { value: "primary", text: tr.settings.general.screenPrimary }),
    h("option", { value: "cursor", text: tr.settings.general.screenCursor }),
  );
  screen.value = settings.screen;
  // A free dock stays on the display it was dropped on.
  screen.disabled = settings.dock === "free";
  screen.addEventListener("change", () => {
    settings.screen = screen.value as Settings["screen"];
    void save();
  });

  return h(
    "section",
    {},
    h("h2", {}, h("span", { text: tr.settings.general.title })),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.language }),
      language,
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.sound }),
      toggle(settings.soundEnabled, (v) => { settings.soundEnabled = v; void save(); }),
      volume,
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.autoClose }),
      autoClose,
      h("span", { class: "hint", text: tr.settings.general.autoCloseHint }),
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.dock }),
      h("span", {
        text: settings.dock === "free" ? tr.settings.general.dockFree : tr.settings.general.dockTop,
      }),
      settings.dock === "free"
        ? h("button", { text: tr.settings.general.dockReset, onclick: () => void Bridge.resetDock() })
        : h("span", { class: "hint", text: tr.settings.general.dockHint }),
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.screen }),
      screen,
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.projectsRoot }),
      projectsRoot,
      h("span", { class: "hint", text: tr.settings.general.projectsRootHint }),
    ),
    h("div", { class: "row" },
      h("label", { text: tr.settings.general.autostart }),
      toggle(settings.autostart, (v) => { settings.autostart = v; void save(); }),
    ),
  );
}

// ── Boot ──────────────────────────────────────────────────────────────────────

/** What the sections are drawn from; read once at launch, kept for redraws. */
let loaded: { status: HookStatus; hasKey: boolean; present: Record<string, boolean> } | null = null;

/** Draws the whole window. Called again when the language changes. */
function render() {
  if (!loaded) return;
  document.title = tr.settings.windowTitle;
  clear(root);
  root.append(
    h("h1", {}, h("span", { text: "VoltaDock" }), h("span", { class: "version", text: version })),
    claudeSection(loaded.status),
    apiSection(loaded.hasKey),
    integrationsSection(loaded.present),
    generalSection(),
    h("div", {
      class: "hint",
      text: tr.settings.privacy,
    }),
  );
}

async function main() {
  const boot = await Bridge.boot();
  if (boot) {
    settings = { ...settings, ...boot.settings };
    version = boot.version;
  }
  setLanguage(settings.language);
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, settingsPath: "", hookPath: "", hookReady: false,
  };

  const hasKey = (await Bridge.secretPresent("anthropic-api-key")) ?? false;

  const keys = [
    "stripe-api-key", "github-token", "vercel-token",
    "n8n-url", "n8n-api-key", "resend-api-key", "notion-api-key", "calcom-api-key",
  ];
  const present: Record<string, boolean> = {};
  for (const k of keys) present[k] = (await Bridge.secretPresent(k)) ?? false;

  loaded = { status, hasKey, present };
  render();

  void onEvent<Settings>("settings-changed", (s) => {
    const dockBefore = `${settings.dock}`;
    settings = { ...settings, ...s };
    if (setLanguage(settings.language)) {
      void refreshLoaded().then(render);
    } else if (settings.dock !== dockBefore) {
      render();
    }
  });
}

/** The key and hook states may have moved since launch: redraw from fresh ones. */
async function refreshLoaded() {
  if (!loaded) return;
  const status = await Bridge.hooksStatus();
  if (status) loaded.status = status;
  loaded.hasKey = (await Bridge.secretPresent("anthropic-api-key")) ?? loaded.hasKey;
  for (const k of Object.keys(loaded.present)) {
    loaded.present[k] = (await Bridge.secretPresent(k)) ?? loaded.present[k];
  }
}

void main();
