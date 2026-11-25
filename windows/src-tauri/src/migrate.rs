// One-time move from the pre-rename layout (the app was called Coucou) to
// VoltaDock's: data folders, log file and the secrets in Credential Manager.
//
// Nothing here ever deletes user data before the new copy is in place, and a
// failure only costs a log line: the app starts either way.
//
// Deliberately NOT touched: Claude Code's settings.json. Its old
// `coucou-hook.exe` entries are replaced the next time the user installs the
// hooks from Settings (they see the diff and confirm), as everywhere else. The
// old relay in %LOCALAPPDATA%\Coucou\bin is left where it is so those entries
// keep working-but-inert (no pipe, exit 0) instead of erroring on every event.

use std::path::Path;

use crate::{log, secrets, settings};

pub fn run() {
    let (old_cfg, old_local) = (legacy_dir("APPDATA"), legacy_dir("LOCALAPPDATA"));
    if let Some(old) = old_cfg {
        move_missing(&old, &settings::config_dir(), &[]);
    }
    if let Some(old) = old_local {
        // `bin` stays: see above. The log is renamed, not carried over as-is.
        move_missing(&old, &settings::local_dir(), &["bin", "coucou.log"]);
    }
    secrets::migrate_legacy();
}

fn legacy_dir(var: &str) -> Option<std::path::PathBuf> {
    let dir = std::path::PathBuf::from(std::env::var_os(var)?).join("Coucou");
    dir.is_dir().then_some(dir)
}

/// Moves every entry of `old` that `new` does not have yet (skipping `skip`).
/// Existing files in `new` always win. Returns how many entries were moved.
pub fn move_missing(old: &Path, new: &Path, skip: &[&str]) -> usize {
    if std::fs::create_dir_all(new).is_err() {
        return 0;
    }
    let Ok(entries) = std::fs::read_dir(old) else { return 0 };
    let mut moved = 0;
    for entry in entries.flatten() {
        let name = entry.file_name();
        if skip.iter().any(|s| name == *s) {
            continue;
        }
        let (from, to) = (entry.path(), new.join(&name));
        if to.exists() {
            if from.is_dir() && to.is_dir() {
                moved += move_missing(&from, &to, &[]);
            }
            continue;
        }
        if std::fs::rename(&from, &to).is_ok() || copy_any(&from, &to).is_ok() {
            moved += 1;
        } else {
            log::line(format!("migration: could not move {}", from.display()));
        }
    }
    if moved > 0 {
        log::line(format!("migration: moved {moved} item(s) from {}", old.display()));
    }
    moved
}

fn copy_any(from: &Path, to: &Path) -> std::io::Result<()> {
    if from.is_dir() {
        std::fs::create_dir_all(to)?;
        for e in std::fs::read_dir(from)? {
            let e = e?;
            copy_any(&e.path(), &to.join(e.file_name()))?;
        }
        Ok(())
    } else {
        std::fs::copy(from, to).map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("voltadock-mig-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn settings_and_inbox_move_and_bin_stays() {
        let root = tmp("a");
        let (old, new) = (root.join("Coucou"), root.join("VoltaDock"));
        std::fs::create_dir_all(old.join("inbox")).unwrap();
        std::fs::create_dir_all(old.join("bin")).unwrap();
        std::fs::write(old.join("settings.json"), "{\"language\":\"es\"}").unwrap();
        std::fs::write(old.join("inbox/a.txt"), "x").unwrap();
        std::fs::write(old.join("bin/coucou-hook.exe"), "x").unwrap();
        assert_eq!(move_missing(&old, &new, &["bin"]), 2);
        assert_eq!(std::fs::read_to_string(new.join("settings.json")).unwrap(), "{\"language\":\"es\"}");
        assert!(new.join("inbox/a.txt").exists());
        assert!(!new.join("bin").exists());
        assert!(old.join("bin/coucou-hook.exe").exists());
    }

    #[test]
    fn existing_new_files_win_and_a_second_run_is_a_no_op() {
        let root = tmp("b");
        let (old, new) = (root.join("Coucou"), root.join("VoltaDock"));
        std::fs::create_dir_all(&old).unwrap();
        std::fs::create_dir_all(&new).unwrap();
        std::fs::write(old.join("settings.json"), "old").unwrap();
        std::fs::write(new.join("settings.json"), "new").unwrap();
        assert_eq!(move_missing(&old, &new, &[]), 0);
        assert_eq!(std::fs::read_to_string(new.join("settings.json")).unwrap(), "new");
        assert_eq!(move_missing(&old, &new, &[]), 0);
    }
}
