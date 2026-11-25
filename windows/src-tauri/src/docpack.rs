// Reads Word, Excel and PowerPoint files with docpack (MIT, bundled as
// docpack.exe next to the app) so Claude gets Markdown and CSV instead of the
// zip bytes. Everything runs locally: docpack makes no network calls, and the
// original file is never modified — the pack is built from the inbox copy and
// deleted right after it has been read.
//
// This only ever runs when the user has the "analyze with docpack" setting on,
// on a file they dropped themselves, and any failure just means the file is
// sent the way it was before (skipped).

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::{files, settings};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
/// A build that takes longer than this is killed: the chat must not hang on a file.
const TIMEOUT: Duration = Duration::from_secs(60);
/// Characters of converted text sent to Claude. The rest is left out, and the
/// message says so.
const MAX_CHARS: usize = 150_000;
const MAX_INDEX_CHARS: usize = 20_000;

/// Extensions docpack reads that the API cannot take natively. PDFs keep
/// going to Claude as documents.
pub fn supports(ext: &str) -> bool {
    matches!(ext, "docx" | "docm" | "xlsx" | "xlsm" | "xls" | "xlsb" | "ods" | "pptx")
}

/// docpack.exe is installed beside the app (a Tauri resource); a copy in
/// %LOCALAPPDATA%\VoltaDock\bin also works.
fn exe_path() -> Option<PathBuf> {
    let beside_app = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|d| d.join("docpack.exe")));
    let local = settings::local_dir().join("bin").join("docpack.exe");
    [beside_app, Some(local)].into_iter().flatten().find(|p| p.is_file())
}

/// Builds the pack for `path` and returns the text to hand to Claude, or None
/// when docpack is missing, fails or times out.
pub fn analyze(path: &str) -> Option<String> {
    let exe = exe_path()?;
    let project = files::inbox_dir();
    let name = Path::new(path).file_name()?.to_string_lossy().to_string();

    let mut cmd = Command::new(exe);
    cmd.arg("build")
        .arg(path)
        .arg("--project")
        .arg(&project)
        .arg("--no-pages")
        .current_dir(&project)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let mut child = cmd.spawn().ok()?;

    let deadline = Instant::now() + TIMEOUT;
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => break,
            Ok(Some(_)) | Err(_) => return None,
            Ok(None) if Instant::now() > deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(50)),
        }
    }
    let mut stdout = String::new();
    child.stdout.take()?.read_to_string(&mut stdout).ok()?;
    let reply: Value = serde_json::from_str(&stdout).ok()?;

    // The pack folder comes from the tool's own output: only trust it when it
    // really is inside the inbox.
    let pack = PathBuf::from(reply.get("pack")?.as_str()?);
    let pack = pack.canonicalize().ok()?;
    if !pack.starts_with(project.canonicalize().ok()?) {
        return None;
    }

    let text = read_pack(&pack, &name);
    let _ = std::fs::remove_dir_all(&pack);
    // `docpack/` is left empty once the pack is gone.
    let _ = std::fs::remove_dir(project.join("docpack"));
    text
}

fn read_pack(pack: &Path, name: &str) -> Option<String> {
    let mut out = format!(
        "File: {name} (converted locally to Markdown/CSV with docpack; the original is a binary Office file)\n"
    );
    let mut budget = MAX_CHARS;
    let mut truncated = false;

    let index = read_text(&pack.join("index.json")).unwrap_or_default();
    let index: String = index.chars().take(MAX_INDEX_CHARS).collect();
    if !index.is_empty() {
        out.push_str("\n=== index.json ===\n");
        out.push_str(&index);
        out.push('\n');
        budget = budget.saturating_sub(index.chars().count());
    }

    for (dir, ext) in [("secciones", "md"), ("tablas", "csv")] {
        for file in sorted_files(&pack.join(dir), ext) {
            let Some(body) = read_text(&file) else { continue };
            let label = format!("\n=== {dir}/{} ===\n", file.file_name()?.to_string_lossy());
            let need = label.chars().count() + body.chars().count();
            if need > budget {
                truncated = true;
                continue;
            }
            budget -= need;
            out.push_str(&label);
            out.push_str(&body);
        }
    }
    if truncated {
        out.push_str("\n[Some sections or tables were left out because the file is large.]\n");
    }
    // Nothing but the header means docpack produced no content.
    (out.len() > 200).then_some(out)
}

fn sorted_files(dir: &Path, ext: &str) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut files: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some(ext))
        .collect();
    files.sort();
    files
}

fn read_text(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(text.trim_start_matches('\u{feff}').to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_office_formats_go_through_docpack() {
        assert!(supports("docx") && supports("xlsx") && supports("pptx"));
        assert!(!supports("pdf") && !supports("png") && !supports("txt"));
    }

    #[test]
    fn reads_sections_then_tables_within_budget() {
        let dir = std::env::temp_dir().join(format!("voltadock-pack-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("secciones")).unwrap();
        std::fs::create_dir_all(dir.join("tablas")).unwrap();
        std::fs::write(dir.join("index.json"), "{\"document\":\"a.docx\"}").unwrap();
        std::fs::write(dir.join("secciones/01-intro.md"), "# Intro\n".repeat(40)).unwrap();
        std::fs::write(dir.join("tablas/T01.csv"), "\u{feff}a,b\n1,2\n").unwrap();
        let text = read_pack(&dir, "a.docx").unwrap();
        assert!(text.contains("=== secciones/01-intro.md ==="));
        assert!(text.contains("=== tablas/T01.csv ===\na,b"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
