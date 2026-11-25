// Preferences, stored as plain JSON in %APPDATA%\VoltaDock\settings.json.
// No secret ever lands here — API keys live in the Windows Credential Manager.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub sound_enabled: bool,
    pub sound_volume: f64,
    pub auto_close_interval: f64,
    pub absence_interval: f64,
    pub active_integrations: Vec<String>,
    /// "primary" = the main display, "cursor" = whichever display the mouse is on.
    pub screen: String,
    pub autostart: bool,
    pub hooks_installed: bool,
    /// Claude model used by the chat. Changeable in the settings window.
    /// Defaulted explicitly so a settings.json written by an older build still loads.
    #[serde(default = "default_model")]
    pub model: String,
    /// Folder whose git repositories the "Proyectos" panel lists. Empty means
    /// the first of the usual places that exists.
    #[serde(default)]
    pub projects_root: String,
    /// Interface language: "es" (default), "en", or "system" to follow Windows.
    #[serde(default = "default_language")]
    pub language: String,
    /// Where the island sits: "top" = top centre of the display picked by
    /// `screen` (the default, like the notch), "free" = docked to the edge the
    /// user dropped it on (`dock_edge`, `dock_pos`).
    #[serde(default = "default_dock")]
    pub dock: String,
    /// Free dock: the display edge the island is attached to — "top", "bottom",
    /// "left" or "right" — and the island opens away from it.
    #[serde(default)]
    pub dock_edge: String,
    /// Free dock: where along that edge, as a fraction (0..1) of the display's
    /// work area. Fractions survive a resolution or scale change.
    #[serde(default = "default_dock_pos")]
    pub dock_pos: f64,
    /// Read only to migrate a settings.json from the first free-dock build
    /// (anchor x/y, no edge); never written back.
    #[serde(default, skip_serializing)]
    pub dock_x: f64,
    #[serde(default, skip_serializing)]
    pub dock_y: f64,
    /// Free dock: name Windows gives the display it was dropped on.
    #[serde(default)]
    pub dock_monitor: String,
    /// Lets a paired iPad connect over the local network (remote.rs). Off by default.
    #[serde(default)]
    pub remote_enabled: bool,
    /// Office files dropped on the island are read with docpack (docpack.rs)
    /// before they go to Claude. On by default; PDFs and images are unaffected.
    #[serde(default = "default_true")]
    pub docpack_enabled: bool,
}

fn default_true() -> bool {
    true
}

fn default_dock() -> String {
    "top".into()
}

fn default_dock_pos() -> f64 {
    0.5
}

fn default_language() -> String {
    "es".into()
}

fn default_model() -> String {
    crate::claude::DEFAULT_MODEL.to_string()
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            sound_enabled: true,
            sound_volume: 0.12,
            auto_close_interval: 15.0,
            absence_interval: 180.0,
            active_integrations: vec![
                "integration_resend".into(),
                "integration_n8n".into(),
                "integration_vercel".into(),
                "integration_github".into(),
            ],
            screen: "primary".into(),
            autostart: false,
            hooks_installed: false,
            model: default_model(),
            projects_root: String::new(),
            remote_enabled: false,
            docpack_enabled: true,
            language: default_language(),
            dock: default_dock(),
            dock_edge: "top".into(),
            dock_pos: 0.5,
            dock_x: 0.0,
            dock_y: 0.0,
            dock_monitor: String::new(),
        }
    }
}

/// %APPDATA%\VoltaDock
pub fn config_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("VoltaDock")
}

/// %LOCALAPPDATA%\VoltaDock — where voltadock-hook.exe and the log live.
pub fn local_dir() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("VoltaDock")
}

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join("voltadock-hook.exe")
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn load() -> Settings {
    let mut s: Settings = match std::fs::read(settings_path()) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => Settings::default(),
    };
    // First free-dock build stored an anchor (x, y) instead of an edge.
    if s.dock_edge.is_empty() {
        if s.dock == "free" {
            s.dock_edge = if s.dock_y > 0.5 { "bottom" } else { "top" }.into();
            s.dock_pos = s.dock_x.clamp(0.0, 1.0);
        } else {
            s.dock_edge = "top".into();
            s.dock_pos = 0.5;
        }
    }
    s
}

pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(settings_path(), json)
}
