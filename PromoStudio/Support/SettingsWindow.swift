import AppKit
import SwiftUI

/// Opens the Settings window in front of other apps. Promo Studio is a menu bar
/// app (`LSUIElement`) and is not active when its menu is used, so
/// `openSettings()` alone opens Settings behind the frontmost app (same fix as
/// Remote Code).
@MainActor
enum SettingsWindow {
    static func show(using openSettings: OpenSettingsAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openSettings()
        // The window exists only after this run-loop turn.
        DispatchQueue.main.async {
            let window = NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
            NSApp.activate()
        }
    }
}
