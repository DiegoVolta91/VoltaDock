// Preferences, stored as plain JSON in %APPDATA%\Coucou\settings.json.
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
    /// `screen` (the default, like the notch), "free" = wherever the user dragged it.
    #[serde(default = "default_dock")]
    pub dock: String,
    /// Free dock: the island's anchor as fractions (0..1) of the display's work
    /// area. The anchor is the middle of the edge the island grows from — its top
    /// edge in the upper half of the display, its bottom edge in the lower half.
    /// Fractions survive a resolution or scale change.
    #[serde(default)]
    pub dock_x: f64,
    #[serde(default)]
    pub dock_y: f64,
    /// Free dock: name Windows gives the display it was dropped on.
    #[serde(default)]
    pub dock_monitor: String,
}

fn default_dock() -> String {
    "top".into()
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
            language: default_language(),
            dock: default_dock(),
            dock_x: 0.5,
            dock_y: 0.0,
            dock_monitor: String::new(),
        }
    }
}

/// %APPDATA%\Coucou
pub fn config_dir() -> PathBuf {
    let base = std::env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("Coucou")
}

/// %LOCALAPPDATA%\Coucou — where coucou-hook.exe and the log live.
pub fn local_dir() -> PathBuf {
    let base = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join("Coucou")
}

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join("coucou-hook.exe")
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn load() -> Settings {
    match std::fs::read(settings_path()) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => Settings::default(),
    }
}

pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(settings_path(), json)
}
