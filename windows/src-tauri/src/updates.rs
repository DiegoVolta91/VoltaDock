// "Is there a newer release?" One GET to GitHub's public releases API, only when
// the user turned it on (or pressed "Buscar ahora"). Nothing about the user or
// the PC is sent: the request carries no identifier beyond a generic client name.

use serde::Serialize;
use std::time::Duration;

const LATEST: &str = "https://api.github.com/repos/DiegoVolta91/VoltaDock/releases/latest";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    /// "newer", "current", "none" (nothing published yet) or "error".
    pub status: String,
    pub version: String,
    pub url: String,
}

fn info(status: &str, version: &str, url: &str) -> UpdateInfo {
    UpdateInfo { status: status.into(), version: version.into(), url: url.into() }
}

/// "v1.2.3" / "1.2.3-beta" → [1, 2, 3]. Missing or odd parts count as 0.
fn parts(v: &str) -> [u64; 3] {
    let core = v.trim().trim_start_matches(['v', 'V']).split(['-', '+']).next().unwrap_or("");
    let mut out = [0u64; 3];
    for (i, p) in core.split('.').take(3).enumerate() {
        out[i] = p.parse().unwrap_or(0);
    }
    out
}

pub async fn check() -> UpdateInfo {
    let client = match reqwest::Client::builder().timeout(Duration::from_secs(8)).build() {
        Ok(c) => c,
        Err(_) => return info("error", "", ""),
    };
    let resp = client
        .get(LATEST)
        .header("User-Agent", "volta-dock-update-check")
        .header("Accept", "application/vnd.github+json")
        .send()
        .await;
    let resp = match resp {
        Ok(r) => r,
        Err(_) => return info("error", "", ""),
    };
    if resp.status() == reqwest::StatusCode::NOT_FOUND {
        return info("none", "", "");
    }
    if !resp.status().is_success() {
        return info("error", "", "");
    }
    let json: serde_json::Value = match resp.json().await {
        Ok(j) => j,
        Err(_) => return info("error", "", ""),
    };
    let tag = json["tag_name"].as_str().unwrap_or("");
    let page = json["html_url"].as_str().unwrap_or("");
    // Only ever hand the front end a link on GitHub itself.
    let page = if page.starts_with("https://github.com/DiegoVolta91/VoltaDock/") { page } else { "" };
    if tag.is_empty() {
        return info("none", "", "");
    }
    if parts(tag) > parts(env!("CARGO_PKG_VERSION")) {
        info("newer", tag.trim_start_matches(['v', 'V']), page)
    } else {
        info("current", env!("CARGO_PKG_VERSION"), page)
    }
}

#[cfg(test)]
mod tests {
    use super::parts;

    #[test]
    fn versions_compare_numerically() {
        assert!(parts("v0.10.0") > parts("0.9.9"));
        assert!(parts("1.0.0") > parts("1.0.0-beta"));
        assert_eq!(parts("v2"), [2, 0, 0]);
    }
}
