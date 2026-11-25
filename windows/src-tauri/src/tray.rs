// Notification-area icon: Open, Focus, Settings, Pause, Quit.

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter};

use crate::island::WINDOW_LABEL;

const TRAY_ID: &str = "coucou";

/// The menu in the current language; rebuilt by `relabel` when it changes.
fn menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let t = crate::i18n::m();
    let open = MenuItem::with_id(app, "open", t.tray_open, true, None::<&str>)?;
    let focus = MenuItem::with_id(app, "focus", t.tray_focus, true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", t.tray_settings, true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause", t.tray_pause, true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", t.tray_quit, true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    Menu::with_items(app, &[&open, &focus, &sep1, &settings, &pause, &sep2, &quit])
}

/// Swaps in a menu in the language now in use.
pub fn relabel(app: &AppHandle) {
    if let (Some(tray), Ok(menu)) = (app.tray_by_id(TRAY_ID), menu(app)) {
        let _ = tray.set_menu(Some(menu));
    }
}

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let menu = menu(app)?;

    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip("VoltaDock")
        .menu(&menu)
        .on_menu_event(|app: &AppHandle, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "settings" => crate::show_settings_window(app),
            id => {
                let _ = app.emit_to(WINDOW_LABEL, "tray", id.to_string());
            }
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        builder = builder.icon(icon);
    }

    builder.build(app)?;
    Ok(())
}
