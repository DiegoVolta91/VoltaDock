// Local-network server for the VoltaDock iPad app. Protocol: docs/REMOTE.md.
//
// Off by default: nothing listens until the user turns on "iPad" in Settings.
// The iPad sees the same hook events as the island and may answer permission
// requests; whoever taps first wins, and the other screen is told.
//
// Every frame after the handshake is ChaCha20-Poly1305 with keys derived from
// the pairing key (shown once as a QR code, kept in the Credential Manager), so
// someone else on the Wi-Fi can neither read the sessions nor approve anything.

use std::collections::HashMap;
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::Serialize;
use serde_json::{json, Map, Value};
use tauri::{AppHandle, Emitter};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{broadcast, mpsc, watch};

use crate::log;

pub const PORT: u16 = 47821;
const MAX_CLIENTS: usize = 4;
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const PING_EVERY: Duration = Duration::from_secs(25);
const IDLE_TIMEOUT: Duration = Duration::from_secs(90);
/// Longest string kept from a hook payload.
const MAX_TEXT: usize = 2000;
const SESSIONS_SENT: usize = 8;

// ── Crypto (kept free of I/O so it can be checked on its own) ─────────────────

pub mod wire {
    use chacha20poly1305::aead::{Aead, KeyInit};
    use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
    use hkdf::Hkdf;
    use sha2::Sha256;

    pub const MAGIC: &[u8; 4] = b"VDR1";
    pub const INFO: &[u8] = b"voltadock-remote/1";
    pub const MAX_FRAME: usize = (1 << 20) + 16;

    /// One direction of an encrypted stream.
    pub struct Cipher {
        aead: ChaCha20Poly1305,
        counter: u64,
    }

    impl Cipher {
        fn new(key: &[u8]) -> Self {
            Self { aead: ChaCha20Poly1305::new(Key::from_slice(key)), counter: 0 }
        }

        fn nonce(&mut self) -> [u8; 12] {
            let mut n = [0u8; 12];
            n[4..].copy_from_slice(&self.counter.to_be_bytes());
            self.counter += 1;
            n
        }

        pub fn seal(&mut self, plain: &[u8]) -> Vec<u8> {
            let n = self.nonce();
            self.aead.encrypt(Nonce::from_slice(&n), plain).expect("chacha20poly1305 encrypt")
        }

        pub fn open(&mut self, sealed: &[u8]) -> Option<Vec<u8>> {
            let n = self.nonce();
            self.aead.decrypt(Nonce::from_slice(&n), sealed).ok()
        }
    }

    /// (iPad → desktop, desktop → iPad) ciphers for one connection.
    pub fn derive(key: &[u8; 32], client_random: &[u8; 32], server_random: &[u8; 32]) -> (Cipher, Cipher) {
        let mut salt = [0u8; 64];
        salt[..32].copy_from_slice(client_random);
        salt[32..].copy_from_slice(server_random);
        let hk = Hkdf::<Sha256>::new(Some(&salt), key);
        let mut okm = [0u8; 64];
        hk.expand(INFO, &mut okm).expect("64 bytes is a valid HKDF length");
        (Cipher::new(&okm[..32]), Cipher::new(&okm[32..]))
    }
}

// ── Shared state ──────────────────────────────────────────────────────────────

struct Hub {
    /// Messages for every connected iPad, already serialised.
    tx: broadcast::Sender<Arc<String>>,
    /// Permission requests still waiting, so an iPad that connects late sees them.
    pending: Mutex<Vec<(String, Value)>>,
    viewers: AtomicUsize,
    /// Last "Hoy" snapshot sent by the island, so an iPad that connects late has it.
    today: Mutex<Option<Value>>,
    /// Bumped to close every connection (stop, or a new pairing key).
    generation: watch::Sender<u64>,
    /// Set while the listener runs.
    running: Mutex<Option<watch::Sender<bool>>>,
    error: Mutex<Option<String>>,
    devices: Mutex<HashMap<u64, String>>,
    next_conn: AtomicUsize,
}

static HUB: LazyLock<Hub> = LazyLock::new(|| Hub {
    tx: broadcast::channel(256).0,
    pending: Mutex::new(Vec::new()),
    viewers: AtomicUsize::new(0),
    today: Mutex::new(None),
    generation: watch::channel(0).0,
    running: Mutex::new(None),
    error: Mutex::new(None),
    devices: Mutex::new(HashMap::new()),
    next_conn: AtomicUsize::new(1),
});

fn is_running() -> bool {
    HUB.running.lock().unwrap().is_some()
}

/// True while at least one paired iPad is connected and past the handshake.
pub fn has_viewers() -> bool {
    HUB.viewers.load(Ordering::Relaxed) > 0
}

fn broadcast(msg: Value) {
    if HUB.viewers.load(Ordering::Relaxed) == 0 {
        return;
    }
    let _ = HUB.tx.send(Arc::new(msg.to_string()));
}

// ── Called by the pipe server ─────────────────────────────────────────────────

/// Every hook event the island gets, trimmed.
pub fn publish_hook(payload: &Value) {
    if !is_running() {
        return;
    }
    let event = slim(payload);
    if event.get("hook_event_name").and_then(Value::as_str) == Some("PermissionRequest") {
        if let Some(id) = event.get("request_id").and_then(Value::as_str) {
            HUB.pending.lock().unwrap().push((id.to_string(), event.clone()));
        }
    }
    broadcast(json!({ "type": "hook", "event": event }));
}

/// The island's Hoy state (focus, goals, reminders), as the webview sees it.
pub fn set_today(state: Value) {
    *HUB.today.lock().unwrap() = Some(state.clone());
    if is_running() {
        broadcast(json!({ "type": "today", "state": state }));
    }
}

/// A request was answered (by anyone) or handed back to the terminal.
pub fn resolved(request_id: &str, decision: Option<&str>) {
    let had = {
        let mut pending = HUB.pending.lock().unwrap();
        let before = pending.len();
        pending.retain(|(id, _)| id != request_id);
        before != pending.len()
    };
    if had {
        broadcast(json!({ "type": "resolved", "request_id": request_id, "decision": decision }));
    }
}

fn is_pending(request_id: &str) -> bool {
    HUB.pending.lock().unwrap().iter().any(|(id, _)| id == request_id)
}

const KEPT_FIELDS: &[&str] = &[
    "hook_event_name",
    "session_id",
    "cwd",
    "request_id",
    "tool_name",
    "tool_input",
    "prompt",
    "message",
    "last_assistant_message",
    "notification_type",
    "error",
    "error_details",
];

fn slim(payload: &Value) -> Value {
    let mut out = Map::new();
    if let Some(obj) = payload.as_object() {
        for key in KEPT_FIELDS {
            if let Some(v) = obj.get(*key) {
                out.insert((*key).to_string(), trim(v, 0));
            }
        }
    }
    Value::Object(out)
}

fn trim(v: &Value, depth: usize) -> Value {
    match v {
        Value::String(s) if s.chars().count() > MAX_TEXT => {
            Value::String(s.chars().take(MAX_TEXT).collect::<String>() + "…")
        }
        Value::Array(a) if depth < 4 => Value::Array(a.iter().take(20).map(|x| trim(x, depth + 1)).collect()),
        Value::Object(o) if depth < 4 => Value::Object(
            o.iter().take(40).map(|(k, x)| (k.clone(), trim(x, depth + 1))).collect(),
        ),
        Value::Array(_) | Value::Object(_) => Value::String("…".into()),
        other => other.clone(),
    }
}

// ── Pairing key ───────────────────────────────────────────────────────────────

fn load_key() -> Option<[u8; 32]> {
    let text = crate::secrets::internal_get(crate::secrets::REMOTE_KEY)?;
    let bytes = URL_SAFE_NO_PAD.decode(text.trim()).ok()?;
    bytes.try_into().ok()
}

fn new_key() -> Result<[u8; 32], String> {
    let mut key = [0u8; 32];
    getrandom::getrandom(&mut key).map_err(|e| e.to_string())?;
    crate::secrets::internal_set(crate::secrets::REMOTE_KEY, &URL_SAFE_NO_PAD.encode(key))?;
    Ok(key)
}

fn key_or_create() -> Result<[u8; 32], String> {
    match load_key() {
        Some(k) => Ok(k),
        None => new_key(),
    }
}

// ── Commands for the settings window ──────────────────────────────────────────

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct RemoteStatus {
    pub running: bool,
    pub port: u16,
    pub viewers: usize,
    pub devices: Vec<String>,
    pub paired: bool,
    pub error: Option<String>,
}

pub fn status() -> RemoteStatus {
    let mut devices: Vec<String> = HUB.devices.lock().unwrap().values().cloned().collect();
    devices.sort();
    RemoteStatus {
        running: is_running(),
        port: PORT,
        viewers: HUB.viewers.load(Ordering::Relaxed),
        devices,
        paired: load_key().is_some(),
        error: HUB.error.lock().unwrap().clone(),
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Pairing {
    /// voltadock://pair?… — the whole secret, shown only on demand.
    pub code: String,
    /// The same, as a QR code.
    pub qr_svg: String,
    pub hosts: Vec<String>,
}

fn computer_name() -> String {
    std::env::var("COMPUTERNAME").unwrap_or_else(|_| "PC".into())
}

/// The address this PC uses on the LAN. Connecting a UDP socket sends nothing:
/// it only asks Windows which interface would be used.
fn lan_ipv4() -> Option<String> {
    let socket = UdpSocket::bind("0.0.0.0:0").ok()?;
    socket.connect("192.168.255.255:9").ok()?;
    match socket.local_addr().ok()? {
        SocketAddr::V4(a) if !a.ip().is_loopback() && !a.ip().is_unspecified() => Some(a.ip().to_string()),
        _ => None,
    }
}

fn pct(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub fn pairing() -> Result<Pairing, String> {
    let key = key_or_create()?;
    let name = computer_name();
    let mut hosts = Vec::new();
    if let Some(ip) = lan_ipv4() {
        hosts.push(ip);
    }
    hosts.push(format!("{}.local", name.to_lowercase()));
    let code = format!(
        "voltadock://pair?v=1&n={}&p={PORT}&h={}&k={}",
        pct(&name),
        hosts.iter().map(|h| pct(h)).collect::<Vec<_>>().join(","),
        URL_SAFE_NO_PAD.encode(key),
    );
    let qr = qrcode::QrCode::new(code.as_bytes()).map_err(|e| e.to_string())?;
    let qr_svg = qr
        .render::<qrcode::render::svg::Color>()
        .min_dimensions(220, 220)
        .dark_color(qrcode::render::svg::Color("#000000"))
        .light_color(qrcode::render::svg::Color("#ffffff"))
        .build();
    Ok(Pairing { code, qr_svg, hosts })
}

/// New key: every paired iPad is disconnected and has to scan again.
pub fn forget(app: &AppHandle) -> Result<(), String> {
    new_key()?;
    HUB.generation.send_modify(|g| *g += 1);
    log::line("remote: pairing key replaced, iPads disconnected");
    notify(app);
    Ok(())
}

fn notify(app: &AppHandle) {
    let _ = app.emit("remote-changed", status());
}

// ── Listener ──────────────────────────────────────────────────────────────────

/// Starts or stops the listener to match the setting.
pub fn apply(app: &AppHandle, enabled: bool) {
    if enabled == is_running() {
        return;
    }
    if !enabled {
        if let Some(stop) = HUB.running.lock().unwrap().take() {
            let _ = stop.send(true);
        }
        HUB.generation.send_modify(|g| *g += 1);
        HUB.pending.lock().unwrap().clear();
        log::line("remote: stopped");
        notify(app);
        return;
    }
    let (stop_tx, stop_rx) = watch::channel(false);
    *HUB.running.lock().unwrap() = Some(stop_tx);
    *HUB.error.lock().unwrap() = None;
    let app = app.clone();
    tauri::async_runtime::spawn(async move { listen(app, stop_rx).await });
}

async fn listen(app: AppHandle, mut stop: watch::Receiver<bool>) {
    let listener = match TcpListener::bind(("0.0.0.0", PORT)).await {
        Ok(l) => l,
        Err(err) => {
            log::line(format!("remote: cannot listen on {PORT}: {err}"));
            *HUB.error.lock().unwrap() = Some(err.to_string());
            HUB.running.lock().unwrap().take();
            notify(&app);
            return;
        }
    };
    log::line(format!("remote: listening on {PORT}"));
    notify(&app);
    loop {
        tokio::select! {
            _ = stop.changed() => break,
            accepted = listener.accept() => {
                let Ok((stream, peer)) = accepted else { continue };
                if HUB.viewers.load(Ordering::Relaxed) >= MAX_CLIENTS {
                    continue;
                }
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    if let Err(why) = serve(app, stream).await {
                        log::line(format!("remote: {peer} closed: {why}"));
                    }
                });
            }
        }
    }
}

async fn read_frame(rd: &mut OwnedReadHalf, cipher: &mut wire::Cipher) -> Result<Value, String> {
    let mut len = [0u8; 4];
    rd.read_exact(&mut len).await.map_err(|e| e.to_string())?;
    let len = u32::from_be_bytes(len) as usize;
    if !(16..=wire::MAX_FRAME).contains(&len) {
        return Err("bad frame length".into());
    }
    let mut buf = vec![0u8; len];
    rd.read_exact(&mut buf).await.map_err(|e| e.to_string())?;
    let plain = cipher.open(&buf).ok_or("bad key or corrupted frame")?;
    serde_json::from_slice(&plain).map_err(|e| e.to_string())
}

async fn write_frame(wr: &mut OwnedWriteHalf, cipher: &mut wire::Cipher, msg: &str) -> Result<(), String> {
    let sealed = cipher.seal(msg.as_bytes());
    let mut out = Vec::with_capacity(sealed.len() + 4);
    out.extend_from_slice(&(sealed.len() as u32).to_be_bytes());
    out.extend_from_slice(&sealed);
    wr.write_all(&out).await.map_err(|e| e.to_string())
}

fn recent_sessions_json(sessions: Vec<crate::sessions::RecentSession>) -> Value {
    serde_json::to_value(sessions).unwrap_or(Value::Array(vec![]))
}

async fn recent_sessions() -> Value {
    let found = tauri::async_runtime::spawn_blocking(|| crate::sessions::recent(SESSIONS_SENT))
        .await
        .unwrap_or_default();
    recent_sessions_json(found)
}

/// Decrements the viewer count however the connection ends.
struct Viewer {
    id: u64,
    app: AppHandle,
}

impl Drop for Viewer {
    fn drop(&mut self) {
        HUB.viewers.fetch_sub(1, Ordering::Relaxed);
        HUB.devices.lock().unwrap().remove(&self.id);
        notify(&self.app);
    }
}

async fn serve(app: AppHandle, stream: TcpStream) -> Result<(), String> {
    let _ = stream.set_nodelay(true);
    let key = load_key().ok_or("not paired")?;
    let mut kill = HUB.generation.subscribe();
    let (mut rd, mut wr) = stream.into_split();

    // Handshake: fresh randoms from both sides.
    let mut hello = [0u8; 36];
    tokio::time::timeout(HANDSHAKE_TIMEOUT, rd.read_exact(&mut hello))
        .await
        .map_err(|_| "handshake timeout")?
        .map_err(|e| e.to_string())?;
    if &hello[..4] != wire::MAGIC {
        return Err("not a VoltaDock client".into());
    }
    let client_random: [u8; 32] = hello[4..].try_into().unwrap();
    let mut server_random = [0u8; 32];
    getrandom::getrandom(&mut server_random).map_err(|e| e.to_string())?;
    let mut reply = Vec::with_capacity(36);
    reply.extend_from_slice(wire::MAGIC);
    reply.extend_from_slice(&server_random);
    wr.write_all(&reply).await.map_err(|e| e.to_string())?;
    let (mut c2s, mut s2c) = wire::derive(&key, &client_random, &server_random);

    // The first frame proves the iPad holds the key.
    let first = tokio::time::timeout(HANDSHAKE_TIMEOUT, read_frame(&mut rd, &mut c2s))
        .await
        .map_err(|_| "no hello")??;
    if first.get("type").and_then(Value::as_str) != Some("hello") {
        return Err("expected hello".into());
    }
    let device: String = first
        .get("device")
        .and_then(Value::as_str)
        .unwrap_or("iPad")
        .chars()
        .take(60)
        .collect();

    // Subscribe before taking the snapshot, so nothing falls in between.
    let mut events = HUB.tx.subscribe();
    let id = HUB.next_conn.fetch_add(1, Ordering::Relaxed) as u64;
    HUB.viewers.fetch_add(1, Ordering::Relaxed);
    HUB.devices.lock().unwrap().insert(id, device.clone());
    let _viewer = Viewer { id, app: app.clone() };
    log::line(format!("remote: {device} connected"));
    notify(&app);

    let pending: Vec<Value> = HUB.pending.lock().unwrap().iter().map(|(_, v)| v.clone()).collect();
    let welcome = json!({
        "type": "welcome",
        "host": computer_name(),
        "version": env!("CARGO_PKG_VERSION"),
        "pending": pending,
        "sessions": recent_sessions().await,
        "today": HUB.today.lock().unwrap().clone(),
    });
    write_frame(&mut wr, &mut s2c, &welcome.to_string()).await?;

    // Reading is not cancel-safe, so it gets its own task and a channel.
    let (in_tx, mut incoming) = mpsc::channel::<Value>(16);
    let reader = tokio::spawn(async move {
        loop {
            match tokio::time::timeout(IDLE_TIMEOUT, read_frame(&mut rd, &mut c2s)).await {
                Ok(Ok(msg)) => {
                    if in_tx.send(msg).await.is_err() {
                        break;
                    }
                }
                _ => break,
            }
        }
    });

    let mut ping = tokio::time::interval(PING_EVERY);
    ping.tick().await;
    let ping_msg = json!({ "type": "ping" }).to_string();
    let result = loop {
        tokio::select! {
            _ = kill.changed() => break Ok(()),
            _ = ping.tick() => {
                if let Err(e) = write_frame(&mut wr, &mut s2c, &ping_msg).await { break Err(e) }
            }
            event = events.recv() => match event {
                Ok(msg) => {
                    if let Err(e) = write_frame(&mut wr, &mut s2c, &msg).await { break Err(e) }
                }
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => break Ok(()),
            },
            msg = incoming.recv() => {
                let Some(msg) = msg else { break Err("connection lost".into()) };
                if let Some(answer) = handle_client(&app, &device, &msg).await {
                    if let Err(e) = write_frame(&mut wr, &mut s2c, &answer.to_string()).await { break Err(e) }
                }
            }
        }
    };
    reader.abort();
    log::line(format!("remote: {device} disconnected"));
    result
}

async fn handle_client(app: &AppHandle, device: &str, msg: &Value) -> Option<Value> {
    let kind = msg.get("type").and_then(Value::as_str).unwrap_or_default();
    let request_id = msg.get("request_id").and_then(Value::as_str).unwrap_or_default();
    match kind {
        "ack" if is_pending(request_id) => crate::pipe::remote_acknowledge(app, request_id),
        "decision" if is_pending(request_id) => {
            let decision = match msg.get("decision").and_then(Value::as_str) {
                Some("allow") => "allow",
                _ => "deny",
            };
            log::line(format!("remote: {device} answered id={request_id} {decision}"));
            crate::pipe::answer(app, request_id, decision);
        }
        // Start/pause focus, tick a goal, add a to-do…: the island's webview owns
        // the Hoy data, so it applies the command and publishes the new state.
        "today_cmd" => {
            let _ = app.emit("remote-today-cmd", msg.clone());
        }
        "refresh" => return Some(json!({ "type": "sessions", "sessions": recent_sessions().await })),
        _ => {}
    }
    None
}
