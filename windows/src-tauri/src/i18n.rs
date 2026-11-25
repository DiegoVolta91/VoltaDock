// Interface language on the Rust side: the tray menu, the settings window title
// and the messages Rust hands to the island (errors, fallbacks). The island's own
// strings live in src/i18n/{es,en}.ts; this file holds the same two languages
// for what the webviews never see before Rust has said it.
//
// "system" follows the Windows display language: Spanish when it is Spanish,
// English otherwise — the same rule the webviews apply to navigator.language.

use std::sync::atomic::{AtomicBool, Ordering};

pub struct Messages {
    pub tray_open: &'static str,
    pub tray_focus: &'static str,
    pub tray_settings: &'static str,
    pub tray_pause: &'static str,
    pub tray_quit: &'static str,
    pub settings_title: &'static str,

    /// Window title and prompt of the terminal that "Continuar" opens. Plain
    /// ASCII: they go through a .cmd script, which cmd reads in the OEM code page.
    pub resume_title: &'static str,
    pub resume_prompt: &'static str,

    pub api_key_missing: &'static str,
    pub claude_declined: &'static str,
    pub unexpected_response: &'static str,
    pub no_response_text: &'static str,
    /// `{err}` is replaced.
    pub network_error: &'static str,
    pub bad_response: &'static str,

    pub no_folders: &'static str,

    pub invalid_key_401: &'static str,
    /// `{code}` is replaced.
    pub api_error: &'static str,
    pub stripe_secret_key: &'static str,
    pub no_connection: &'static str,
    pub token_scope: &'static str,
    pub token_access: &'static str,
    pub key_access: &'static str,
    pub integration_access: &'static str,
    pub untitled: &'static str,

    /// `{path}` and `{err}` are replaced.
    pub cant_read: &'static str,
    pub not_object: &'static str,
    pub invalid_json: &'static str,
    pub changed_since_preview: &'static str,
    pub backup_failed: &'static str,
    pub write_failed: &'static str,
    pub no_change: &'static str,

    pub detached_head: &'static str,
}

pub const ES: Messages = Messages {
    tray_open: "Abrir VoltaDock",
    tray_focus: "Empezar 25 min de enfoque",
    tray_settings: "Ajustes…",
    tray_pause: "Pausar",
    tray_quit: "Salir",
    settings_title: "Ajustes — VoltaDock",

    resume_title: "Claude - continuar",
    resume_prompt: "Continua donde te quedaste",

    api_key_missing: "Falta la clave de API. Abre los ajustes.",
    claude_declined: "Claude rechazó esta petición.",
    unexpected_response: "Respuesta inesperada de la API.",
    no_response_text: "Sin texto de respuesta.",
    network_error: "Error de red: {err}",
    bad_response: "Respuesta de la API no válida: {err}",

    no_folders: "Aún no se pueden soltar carpetas.",

    invalid_key_401: "Clave de API no válida (401)",
    api_error: "Error de API {code}",
    stripe_secret_key: "Usa una clave secreta (sk_live_…, no pk_live_…)",
    no_connection: "Sin conexión: {err}",
    token_scope: "Al token le faltan permisos",
    token_access: "El token no tiene acceso",
    key_access: "La clave no tiene acceso",
    integration_access: "La integración no tiene acceso",
    untitled: "Sin título",

    cant_read: "No se puede leer {path}: {err}",
    not_object: "{path} no es un objeto JSON: VoltaDock no lo va a tocar.",
    invalid_json: "{path} no es un JSON válido ({err}). Corrígelo o muévelo y vuelve a intentarlo: VoltaDock no lo va a sobrescribir.",
    changed_since_preview: "{path} cambió desde la vista previa. No se escribió nada: revisa el nuevo diff.",
    backup_failed: "Falló la copia de seguridad: {err}",
    write_failed: "Falló la escritura: {err}",
    no_change: "Sin cambios.",

    detached_head: "HEAD suelta",
};

pub const EN: Messages = Messages {
    tray_open: "Open VoltaDock",
    tray_focus: "Start a 25 min focus",
    tray_settings: "Settings…",
    tray_pause: "Pause",
    tray_quit: "Quit",
    settings_title: "Settings — VoltaDock",

    resume_title: "Claude - continue",
    resume_prompt: "Continue where you left off",

    api_key_missing: "API key missing. Open settings.",
    claude_declined: "Claude declined this one.",
    unexpected_response: "Unexpected API response.",
    no_response_text: "No response text.",
    network_error: "Network error: {err}",
    bad_response: "Bad API response: {err}",

    no_folders: "Folders can't be dropped yet.",

    invalid_key_401: "Invalid API key (401)",
    api_error: "API error {code}",
    stripe_secret_key: "Use a secret key (sk_live_… not pk_live_…)",
    no_connection: "No connection: {err}",
    token_scope: "Token lacks the needed scope",
    token_access: "Token lacks access",
    key_access: "Key lacks access",
    integration_access: "Integration lacks access",
    untitled: "Untitled",

    cant_read: "Can't read {path}: {err}",
    not_object: "{path} isn't a JSON object — VoltaDock won't touch it.",
    invalid_json: "{path} isn't valid JSON ({err}). Fix or move it, then try again — VoltaDock won't overwrite it.",
    changed_since_preview: "{path} changed since the preview. Nothing was written — review the new diff.",
    backup_failed: "backup failed: {err}",
    write_failed: "write failed: {err}",
    no_change: "No change.",

    detached_head: "detached HEAD",
};

static ENGLISH: AtomicBool = AtomicBool::new(false);

/// The messages for the language in use.
pub fn m() -> &'static Messages {
    if ENGLISH.load(Ordering::Relaxed) { &EN } else { &ES }
}

/// Applies the `language` setting ("system", "es" or "en"). Returns true when
/// the language in use changed.
pub fn apply(pref: &str) -> bool {
    let english = match pref {
        "es" => false,
        "en" => true,
        _ => !system_is_spanish(),
    };
    ENGLISH.swap(english, Ordering::Relaxed) != english
}

/// Fills `{name}` placeholders: `fill(m().api_error, &[("code", "500")])`.
pub fn fill(template: &str, args: &[(&str, &str)]) -> String {
    let mut out = template.to_string();
    for (name, value) in args {
        out = out.replace(&format!("{{{name}}}"), value);
    }
    out
}

#[cfg(windows)]
fn system_is_spanish() -> bool {
    use windows::Win32::Globalization::GetUserDefaultUILanguage;
    // The low 10 bits of a LANGID are the primary language; LANG_SPANISH = 0x0A.
    let lang = unsafe { GetUserDefaultUILanguage() };
    lang & 0x3FF == 0x0A
}

#[cfg(not(windows))]
fn system_is_spanish() -> bool {
    std::env::var("LANG").map(|l| l.starts_with("es")).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fill_replaces_every_placeholder() {
        assert_eq!(
            fill("{path} isn't valid JSON ({err})", &[("path", "a.json"), ("err", "eof")]),
            "a.json isn't valid JSON (eof)"
        );
    }
}
