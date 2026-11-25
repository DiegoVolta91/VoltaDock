// API keys live in the Windows Credential Manager, never on disk and never in
// the front end — the island can only ask whether a key is present.

use keyring::Entry;

const SERVICE: &str = "io.github.diegovolta91.voltadock";
/// Service name used before the rename; read once by `migrate_legacy`.
const LEGACY_SERVICE: &str = "fr.louisraille.coucou";

/// Every key VoltaDock may store. Anything outside this list is refused.
pub const KNOWN_KEYS: &[&str] = &[
    "anthropic-api-key",
    "n8n-url",
    "n8n-api-key",
    "vercel-token",
    "github-token",
    "stripe-api-key",
    "resend-api-key",
    "notion-api-key",
    "calcom-api-key",
];

fn entry(key: &str) -> Option<Entry> {
    if !KNOWN_KEYS.contains(&key) {
        return None;
    }
    Entry::new(SERVICE, key).ok()
}

pub fn get(key: &str) -> Option<String> {
    entry(key)?.get_password().ok().filter(|v| !v.is_empty())
}

pub fn set(key: &str, value: &str) -> Result<(), String> {
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    if value.is_empty() {
        let _ = entry.delete_credential();
        return Ok(());
    }
    entry.set_password(value).map_err(|e| e.to_string())
}

pub fn clear(key: &str) -> Result<(), String> {
    let entry = entry(key).ok_or_else(|| format!("unknown key {key}"))?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn present(key: &str) -> bool {
    get(key).is_some()
}

/// The iPad pairing key. Deliberately not in KNOWN_KEYS: the settings window can
/// neither set nor clear it, only Rust can (see remote.rs).
pub const REMOTE_KEY: &str = "remote-pairing-key";

pub fn internal_get(key: &str) -> Option<String> {
    Entry::new(SERVICE, key).ok()?.get_password().ok().filter(|v| !v.is_empty())
}

pub fn internal_set(key: &str, value: &str) -> Result<(), String> {
    Entry::new(SERVICE, key)
        .map_err(|e| e.to_string())?
        .set_password(value)
        .map_err(|e| e.to_string())
}

/// Copies every secret stored under the pre-rename service name to the current
/// one (API keys and the iPad pairing key), so an upgrade keeps them. The old
/// entry is deleted only after the new one reads back identically; anything
/// already stored under the new name wins. Failures are logged, never fatal.
pub fn migrate_legacy() {
    for key in KNOWN_KEYS.iter().copied().chain(std::iter::once(REMOTE_KEY)) {
        let Some(old) = Entry::new(LEGACY_SERVICE, key).ok() else { continue };
        let Some(value) = old.get_password().ok().filter(|v| !v.is_empty()) else { continue };
        if internal_get(key).is_none() && internal_set(key, &value).is_err() {
            crate::log::line(format!("migration: could not copy secret {key}"));
            continue;
        }
        if internal_get(key).is_some() {
            let _ = old.delete_credential();
        }
    }
}
