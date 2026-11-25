// Island window: placement on the chosen display, the two window sizes
// (full panel / invisible wake strip), click-through and the cursor poll.
//
// There is no notch on a PC, so the island is a black shape drawn inside a
// borderless, transparent, always-on-top window that never takes focus. By
// default it sits at the top centre of the display, like the notch; the user can
// also drag it anywhere ("free" dock), and it then grows downwards in the upper
// half of a display and upwards in the lower half.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewWindow};

use crate::settings::Settings;

use windows::Win32::Foundation::{HWND, POINT};
use windows::core::BOOL;
use windows::Win32::Foundation::LPARAM;
use windows::Win32::System::Ole::RevokeDragDrop;
use windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON};
use windows::Win32::UI::WindowsAndMessaging::{EnumChildWindows, GetClassNameW};
use windows::Win32::UI::WindowsAndMessaging::{
    GetCursorPos, GetWindowLongPtrW, SetWindowLongPtrW, GWL_EXSTYLE, WS_EX_NOACTIVATE,
    WS_EX_TOOLWINDOW,
};

/// Logical size of the full window — the largest island view, like the macOS panel.
pub const PANEL_W: f64 = 720.0;
pub const PANEL_H: f64 = 320.0;
/// Logical size of the invisible strip that wakes the island when it is hidden.
pub const STRIP_W: f64 = 240.0;
pub const STRIP_H: f64 = 6.0;

/// Logical size of the small visible handle a free-placed island shrinks to when
/// hidden. Away from the top edge an invisible strip could never be found again.
pub const HANDLE_W: f64 = 120.0;
pub const HANDLE_H: f64 = 14.0;

/// A drop whose top edge lands this close to the top of a display sticks the
/// island to that edge (flat top, like the notch), in logical px.
const SNAP_TOP: f64 = 24.0;
/// Stuck to the top edge this close to the middle → back to the default place.
const SNAP_CENTRE: f64 = 32.0;
/// Pointer travel, in physical px, before a press on the island becomes a move.
const DRAG_THRESHOLD: f64 = 6.0;

pub const WINDOW_LABEL: &str = "island";

/// Margin around the island that still counts as "on the island", in logical px.
/// Wider than the macOS 6 pt because a click must never be swallowed.
const HIT_MARGIN: f64 = 14.0;

#[derive(Serialize, Clone)]
pub struct CursorPayload {
    pub x: f64,
    pub y: f64,
}

#[derive(Serialize, Clone)]
pub struct ScreenInfo {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    pub scale: f64,
}

/// The island shape in window-logical coordinates, pushed by the front end.
/// The poll thread owns the click-through decision so it lands in the same 16 ms
/// tick as the cursor read — an IPC round trip here loses clicks.
#[derive(Clone, Copy, Default)]
pub struct IslandRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

/// Wakes / parks the cursor poll thread so a hidden island costs literally nothing.
pub struct PollGate {
    active: Mutex<bool>,
    cv: Condvar,
    pub collapsed: AtomicBool,
    pub rect: Mutex<IslandRect>,
    /// Mirrors the window flag so we only call into Win32 when it changes.
    ignoring: AtomicBool,
    /// A press on the island is being watched for a move.
    drag_armed: AtomicBool,
    /// The island is following the pointer: nothing else may place the window.
    moving: AtomicBool,
}

impl PollGate {
    pub fn new() -> Self {
        Self {
            active: Mutex::new(false),
            cv: Condvar::new(),
            collapsed: AtomicBool::new(true),
            rect: Mutex::new(IslandRect::default()),
            ignoring: AtomicBool::new(false),
            drag_armed: AtomicBool::new(false),
            moving: AtomicBool::new(false),
        }
    }

    pub fn set_rect(&self, rect: IslandRect) {
        *self.rect.lock().unwrap() = rect;
    }

    /// Forces the next poll tick to re-apply the flag (after a window resize).
    pub fn forget_ignore_state(&self) {
        self.ignoring.store(false, Ordering::Relaxed);
    }

    pub fn set_active(&self, on: bool) {
        let mut guard = self.active.lock().unwrap();
        *guard = on;
        self.cv.notify_all();
    }

    fn wait_until_active(&self) {
        let mut guard = self.active.lock().unwrap();
        while !*guard {
            guard = self.cv.wait(guard).unwrap();
        }
    }

    fn is_active(&self) -> bool {
        *self.active.lock().unwrap()
    }
}

pub fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(WINDOW_LABEL)
}

fn cursor_physical() -> Option<(f64, f64)> {
    let mut p = POINT::default();
    unsafe { GetCursorPos(&mut p).ok()? };
    Some((p.x as f64, p.y as f64))
}

/// Lets dropped files reach the app again.
///
/// wry installs its drop target by walking the webview's child windows **once**,
/// when the webview is created. WebView2 creates `Chrome_RenderWidgetHostHWND`
/// later and registers its own target on it; being the innermost window, that one
/// wins, and since the page has no HTML5 drop handler it refuses everything — the
/// "no drop" cursor, with nothing reaching Tauri. Revoking it makes OLE fall
/// through to the target wry registered on the parent widget, which is the one
/// that feeds Tauri's drag events.
///
/// Cheap and idempotent, so it is simply re-run whenever a drag might be starting.
/// Besides the press seen by the cursor poll, it also runs whenever the island
/// collapses and shortly after launch: the poll is parked while the island is
/// hidden, and a file dragged from Explorer onto the wake strip starts its drag
/// before the poll could ever see the press. Returns how many targets it released.
pub fn unblock_webview_drops(app: &AppHandle) -> u32 {
    let mut released: u32 = 0;
    for label in [WINDOW_LABEL, "settings"] {
        let Some(win) = app.get_webview_window(label) else { continue };
        let Some(hwnd) = hwnd_of(&win) else { continue };
        unsafe {
            let _ = EnumChildWindows(
                Some(hwnd),
                Some(revoke_render_widget),
                LPARAM(&mut released as *mut u32 as isize),
            );
        }
    }
    released
}

unsafe extern "system" fn revoke_render_widget(hwnd: HWND, count: LPARAM) -> BOOL {
    let mut name = [0u16; 64];
    let len = unsafe { GetClassNameW(hwnd, &mut name) };
    if len > 0 {
        let class = String::from_utf16_lossy(&name[..len as usize]);
        if class == "Chrome_RenderWidgetHostHWND" && unsafe { RevokeDragDrop(hwnd) }.is_ok() {
            unsafe { *(count.0 as *mut u32) += 1 };
        }
    }
    true.into()
}

/// Runs `unblock_webview_drops` on the main thread and logs when it actually
/// had something to release, so a drop that never arrives can be traced.
pub fn unblock_webview_drops_later(app: &AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let n = unblock_webview_drops(&handle);
        if n > 0 {
            crate::log::line(format!("drop target: released {n} WebView2 target(s)"));
        }
    });
}

/// True while the left mouse button is held — the only signal we get that a
/// drag might be in flight before it reaches the window.
fn left_button_down() -> bool {
    unsafe { (GetAsyncKeyState(VK_LBUTTON.0 as i32) as u16 & 0x8000) != 0 }
}

fn monitor_contains(m: &Monitor, x: f64, y: f64) -> bool {
    let p = m.position();
    let s = m.size();
    x >= p.x as f64
        && x < (p.x + s.width as i32) as f64
        && y >= p.y as f64
        && y < (p.y + s.height as i32) as f64
}

fn is_free(s: &Settings) -> bool {
    s.dock == "free"
}

/// The display the island lives on: for a free dock the one it was dropped on,
/// otherwise the primary one or the one under the cursor.
fn target_monitor(app: &AppHandle, s: &Settings) -> Option<Monitor> {
    let monitors = app.available_monitors().ok()?;
    if is_free(s) && !s.dock_monitor.is_empty() {
        if let Some(m) = monitors
            .iter()
            .find(|m| m.name().is_some_and(|n| *n == s.dock_monitor))
        {
            return Some(m.clone());
        }
        // That display is gone: keep the same spot on the primary one.
    }
    if !is_free(s) && s.screen == "cursor" {
        if let Some((cx, cy)) = cursor_physical() {
            if let Some(m) = monitors.iter().find(|m| monitor_contains(m, cx, cy)) {
                return Some(m.clone());
            }
        }
    }
    app.primary_monitor()
        .ok()
        .flatten()
        .or_else(|| monitors.into_iter().next())
}

pub fn screen_info(app: &AppHandle, s: &Settings) -> ScreenInfo {
    match target_monitor(app, s) {
        Some(m) => {
            let scale = m.scale_factor();
            let p = m.position();
            let s = m.size();
            ScreenInfo {
                x: p.x as f64 / scale,
                y: p.y as f64 / scale,
                width: s.width as f64 / scale,
                height: s.height as f64 / scale,
                scale,
            }
        }
        None => ScreenInfo { x: 0.0, y: 0.0, width: 1920.0, height: 1080.0, scale: 1.0 },
    }
}

/// `v` kept inside `lo..=hi`; the middle when the range is empty (a display
/// smaller than the panel).
fn clamp_range(v: f64, lo: f64, hi: f64) -> f64 {
    if lo > hi { (lo + hi) / 2.0 } else { v.clamp(lo, hi) }
}

/// Work area of a display (the screen minus the taskbar), physical px.
fn work_area(m: &Monitor) -> (f64, f64, f64, f64) {
    let wa = m.work_area();
    (
        wa.position.x as f64,
        wa.position.y as f64,
        (wa.size.width as f64).max(1.0),
        (wa.size.height as f64).max(1.0),
    )
}

/// Free dock: the anchor in physical px, kept where the whole panel fits on the
/// display, and whether the island grows upwards from it.
fn free_anchor(m: &Monitor, s: &Settings) -> (f64, f64, bool) {
    let scale = m.scale_factor();
    let (wx, wy, ww, wh) = work_area(m);
    let up = s.dock_y > 0.5;
    let half_w = PANEL_W * scale / 2.0;
    let ph = PANEL_H * scale;
    let ax = clamp_range(wx + s.dock_x * ww, wx + half_w, wx + ww - half_w);
    let ay = wy + s.dock_y * wh;
    let ay = if up {
        clamp_range(ay, wy + ph, wy + wh)
    } else {
        clamp_range(ay, wy, wy + wh - ph)
    };
    (ax, ay, up)
}

fn is_moving(app: &AppHandle) -> bool {
    app.try_state::<crate::Shared>()
        .is_some_and(|s| s.gate.moving.load(Ordering::Relaxed))
}

/// Places and sizes the window. `collapsed` picks the wake strip (or, for a free
/// dock, the visible handle) instead of the panel.
pub fn apply_geometry(app: &AppHandle, s: &Settings, collapsed: bool) {
    // Mid-drag the pointer owns the window; the drop places it for good.
    if is_moving(app) {
        return;
    }
    let Some(win) = window(app) else { return };
    let Some(m) = target_monitor(app, s) else { return };

    let scale = m.scale_factor();
    let mp = *m.position();
    let ms = *m.size();

    let (lw, lh) = match (collapsed, is_free(s)) {
        (false, _) => (PANEL_W, PANEL_H),
        (true, false) => (STRIP_W, STRIP_H),
        (true, true) => (HANDLE_W, HANDLE_H),
    };
    let pw = (lw * scale).round().max(1.0) as u32;
    let ph = (lh * scale).round().max(1.0) as u32;
    let (x, y) = if is_free(s) {
        let (ax, ay, up) = free_anchor(&m, s);
        let x = (ax - pw as f64 / 2.0).round() as i32;
        let y = if up { (ay - ph as f64).round() as i32 } else { ay.round() as i32 };
        (x, y)
    } else {
        (mp.x + (ms.width as i32 - pw as i32) / 2, mp.y)
    };

    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_position(PhysicalPosition::new(x, y));
    // Moving across displays can rescale the window: re-assert the physical size.
    let _ = win.set_size(PhysicalSize::new(pw, ph));
    let _ = win.set_always_on_top(true);
}

fn hwnd_of(win: &WebviewWindow) -> Option<HWND> {
    let raw = win.hwnd().ok()?.0 as isize;
    if raw == 0 {
        return None;
    }
    Some(HWND(raw as *mut _))
}

/// WS_EX_NOACTIVATE keeps clicks from stealing focus; WS_EX_TOOLWINDOW keeps the
/// island out of Alt-Tab.
pub fn make_non_activating(win: &WebviewWindow) {
    let Some(hwnd) = hwnd_of(win) else { return };
    unsafe {
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let want = ex | WS_EX_NOACTIVATE.0 as isize | WS_EX_TOOLWINDOW.0 as isize;
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    }
}

/// Temporarily allow activation so a text field inside the island can be typed in.
pub fn set_activating(win: &WebviewWindow, activating: bool) {
    let Some(hwnd) = hwnd_of(win) else { return };
    unsafe {
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        let want = if activating {
            ex & !(WS_EX_NOACTIVATE.0 as isize)
        } else {
            ex | WS_EX_NOACTIVATE.0 as isize
        };
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, want);
    }
}

/// Position, size and scale of the monitor the island lives on. Any change here
/// means the island has to be placed again.
fn current_screen_key(app: &AppHandle) -> Option<(i32, i32, u32, u32, u64)> {
    let settings = app
        .try_state::<crate::Shared>()
        .map(|s| s.settings.lock().unwrap().clone())
        .unwrap_or_default();
    let m = target_monitor(app, &settings)?;
    let p = m.position();
    let size = m.size();
    Some((p.x, p.y, size.width, size.height, m.scale_factor().to_bits()))
}

/// Emits `cursor` (window-logical coordinates) at ~60 Hz while the island is
/// visible. Parked on a condvar the rest of the time.
pub fn spawn_cursor_poll(app: AppHandle, gate: Arc<PollGate>) {
    std::thread::spawn(move || {
        let mut was_down = false;
        // Remembered across wakes so a display change while hidden is noticed the
        // moment the island comes back.
        let mut last_screen: Option<(i32, i32, u32, u32, u64)> = None;
        loop {
            gate.wait_until_active();
            let mut last = (f64::MIN, f64::MIN);
            let mut ticks: u32 = 0;
            while gate.is_active() {
                std::thread::sleep(Duration::from_millis(16));

                // Monitors get plugged in, unplugged, rearranged and rescaled, and
                // an island pinned to coordinates that no longer exist is an island
                // nobody can reach. Checked about twice a second — the cursor poll
                // is already running, so this costs one monitor query.
                ticks = ticks.wrapping_add(1);
                if ticks % 30 == 0 {
                    let now = current_screen_key(&app);
                    if now.is_some() && now != last_screen {
                        let first = last_screen.is_none();
                        last_screen = now;
                        if !first {
                            crate::log::line("display layout changed — repositioning".to_string());
                            let _ = app.emit_to(WINDOW_LABEL, "screen-changed", ());
                        }
                    }
                }

                let Some(win) = window(&app) else { continue };
                let Ok(origin) = win.outer_position() else { continue };
                let scale = win.scale_factor().unwrap_or(1.0);
                let Some((cx, cy)) = cursor_physical() else { continue };
                let x = (cx - origin.x as f64) / scale;
                let y = (cy - origin.y as f64) / scale;
                let size = match win.inner_size() {
                    Ok(s) => (s.width as f64 / scale, s.height as f64 / scale),
                    Err(_) => (PANEL_W, PANEL_H),
                };
                if (x - last.0).abs() < 1.0 && (y - last.1).abs() < 1.0 {
                    continue;
                }
                last = (x, y);

                // Click-through: the window only takes the mouse over the island
                // shape. A small entry margin means the flag is already off by the
                // time a moving cursor reaches a button.
                let r = *gate.rect.lock().unwrap();
                let on_island = r.w > 0.0
                    && x >= r.x - HIT_MARGIN
                    && x <= r.x + r.w + HIT_MARGIN
                    && y >= r.y - HIT_MARGIN
                    && y <= r.y + r.h + HIT_MARGIN;

                // A file being dragged has to be able to find us. WS_EX_TRANSPARENT
                // — what click-through is on Windows — hides the window from
                // WindowFromPoint, so OLE finds no drop target and shows the "no
                // drop" cursor. macOS has no such problem: AppKit delivers drags to
                // registered destinations whatever ignoresMouseEvents says. So while
                // a button is held anywhere over the panel, the whole panel takes
                // the mouse, which also makes the drop zone as forgiving as the Mac's.
                // A press may be the start of a drag: make sure the drop target is
                // ours before the file arrives.
                let down = left_button_down();
                if down && !was_down {
                    let handle = app.clone();
                    let _ = app.run_on_main_thread(move || {
                        unblock_webview_drops(&handle);
                    });
                }
                was_down = down;

                let dragging = down
                    && x >= 0.0
                    && x <= size.0
                    && y >= 0.0
                    && y <= size.1;

                let accept = on_island || dragging;
                if gate.ignoring.load(Ordering::Relaxed) == accept {
                    gate.ignoring.store(!accept, Ordering::Relaxed);
                    let _ = win.set_ignore_cursor_events(!accept);
                }

                let _ = win.emit("cursor", CursorPayload { x, y });
            }
        }
    });
}

pub fn set_ignore_cursor(app: &AppHandle, ignore: bool) {
    if let Some(win) = window(app) {
        let _ = win.set_ignore_cursor_events(ignore);
    }
}

// ── Moving the island ────────────────────────────────────────────────────────

/// Called on a press on the island (not on a button). Watches the left button
/// from the Win32 side: if the pointer travels past the threshold before the
/// release, the window follows it, and the drop becomes the new place.
///
/// Emits `dock-drag` with "start" when the move begins, then "end" after a move
/// or "click" when the button came up without one — the front end holds back a
/// compact-island click until then, so a move never opens the island.
pub fn begin_drag(app: AppHandle) {
    let Some(shared) = app.try_state::<crate::Shared>() else { return };
    let gate = shared.gate.clone();
    if gate.drag_armed.swap(true, Ordering::AcqRel) {
        return;
    }
    std::thread::spawn(move || {
        let moved = follow_pointer(&app, &gate);
        gate.moving.store(false, Ordering::Release);
        if moved {
            finish_drag(&app);
        }
        gate.drag_armed.store(false, Ordering::Release);
        let _ = app.emit_to(WINDOW_LABEL, "dock-drag", if moved { "end" } else { "click" });
    });
}

/// Moves the window with the pointer until the button is released. True when it moved.
fn follow_pointer(app: &AppHandle, gate: &PollGate) -> bool {
    let Some(win) = window(app) else { return false };
    let Some((sx, sy)) = cursor_physical() else { return false };
    let Ok(start) = win.outer_position() else { return false };
    let mut moved = false;
    // The press may already be over by the time this thread runs.
    while left_button_down() {
        std::thread::sleep(Duration::from_millis(8));
        let Some((cx, cy)) = cursor_physical() else { continue };
        let (dx, dy) = (cx - sx, cy - sy);
        if !moved {
            if dx.abs().max(dy.abs()) < DRAG_THRESHOLD {
                continue;
            }
            moved = true;
            gate.moving.store(true, Ordering::Release);
            let _ = app.emit_to(WINDOW_LABEL, "dock-drag", "start");
        }
        let _ = win.set_position(PhysicalPosition::new(
            start.x + dx.round() as i32,
            start.y + dy.round() as i32,
        ));
    }
    moved
}

/// Turns where the island was dropped into the stored dock, then places the
/// window properly (kept on screen, growing the right way).
fn finish_drag(app: &AppHandle) {
    let Some(shared) = app.try_state::<crate::Shared>() else { return };
    let Some(win) = window(app) else { return };
    let (Ok(pos), Ok(size)) = (win.outer_position(), win.outer_size()) else { return };
    let scale = win.scale_factor().unwrap_or(1.0);
    let old = shared.settings.lock().unwrap().clone();
    let was_up = is_free(&old) && old.dock_y > 0.5;

    // Where the island shape itself ended up, in physical px.
    let ih = shared.gate.rect.lock().unwrap().h.max(1.0) * scale;
    let ax = pos.x as f64 + size.width as f64 / 2.0;
    let top = if was_up { pos.y as f64 + size.height as f64 - ih } else { pos.y as f64 };
    let bottom = top + ih;
    let cy = (top + bottom) / 2.0;

    let monitors = app.available_monitors().unwrap_or_default();
    let primary = app.primary_monitor().ok().flatten();
    let Some(m) = monitors
        .iter()
        .find(|m| monitor_contains(m, ax, cy))
        .cloned()
        .or_else(|| primary.clone())
        .or_else(|| monitors.first().cloned())
    else {
        return;
    };
    let ms = m.scale_factor();
    let (wx, wy, ww, wh) = work_area(&m);

    let mut next = old.clone();
    next.dock = "free".into();
    next.dock_monitor = m.name().cloned().unwrap_or_default();
    next.dock_x = ((ax - wx) / ww).clamp(0.0, 1.0);
    if top - wy <= SNAP_TOP * ms {
        // Stuck to the top edge. Near the middle of the display the island would
        // live on anyway, that is simply the default place again.
        next.dock_y = 0.0;
        if (ax - (wx + ww / 2.0)).abs() <= SNAP_CENTRE * ms {
            next.dock_x = 0.5;
            let is_primary = primary.as_ref().is_some_and(|p| p.name() == m.name());
            if old.screen == "primary" && is_primary {
                next.dock = "top".into();
            }
        }
    } else if (cy - wy) / wh > 0.5 {
        // Lower half: anchored on its bottom edge, opens upwards.
        next.dock_y = ((bottom - wy) / wh).clamp(0.5001, 1.0);
    } else {
        next.dock_y = ((top - wy) / wh).clamp(0.0, 0.5);
    }

    store_dock(app, next);
}

/// Saves a new dock, re-places the window and tells both windows.
pub fn store_dock(app: &AppHandle, next: Settings) {
    let Some(shared) = app.try_state::<crate::Shared>() else { return };
    *shared.settings.lock().unwrap() = next.clone();
    if let Err(err) = crate::settings::save(&next) {
        eprintln!("[voltadock] could not save settings: {err}");
    }
    crate::log::line(format!(
        "dock: {} x={:.3} y={:.3} on {:?}",
        next.dock, next.dock_x, next.dock_y, next.dock_monitor
    ));
    let collapsed = shared.gate.collapsed.load(Ordering::Relaxed);
    apply_geometry(app, &next, collapsed);
    // The resize can leave the click-through flag stale.
    shared.gate.forget_ignore_state();
    let _ = app.emit("settings-changed", next);
}

/// Back to the top centre of the display.
pub fn reset_dock(app: &AppHandle) {
    let Some(shared) = app.try_state::<crate::Shared>() else { return };
    let mut next = shared.settings.lock().unwrap().clone();
    next.dock = "top".into();
    next.dock_x = 0.5;
    next.dock_y = 0.0;
    next.dock_monitor.clear();
    store_dock(app, next);
}
