import SwiftUI

enum WindowID {
    static let studio = "main"
    static let menuPreview = "menu-preview"
}

/// Menu-bar-first app (`LSUIElement`, like Remote Code): the menu bar panel always
/// runs; the Dock icon is only visible while the studio or Settings window is open.
@main
struct PromoStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Promo Studio", id: WindowID.studio) {
            RootView()
                .environment(delegate.model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(after: .help) {
                Button("Setup Checklist…") {
                    delegate.model.openStudio()
                    delegate.model.showSetup = true
                }
            }
        }

        Settings {
            SettingsView()
                .environment(delegate.model)
        }

        #if DEBUG
        // Menu panel as a normal window (for screenshots and testing): PROMO_STUDIO_PREVIEW_MENU=1
        Window(Text(verbatim: "Menu Preview"), id: WindowID.menuPreview) {
            MenuPanelView()
                .environment(delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow, Self.isAppWindow(window) { NSApp.setActivationPolicy(.regular) }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            // Check after the window has closed: leave the Dock if no other app windows remain
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isAppWindow($0) }
                    if !open { NSApp.setActivationPolicy(.accessory) }
                }
            }
        })
    }

    /// Show the studio when reopened from the Dock or Finder
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openStudio() }
        return true
    }

    /// The scheduler keeps running from the menu bar even when the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Studio, Settings and other titled windows; excludes the menu bar panel and sheets (NSPanel)
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
    }
}

/// Menu bar icon: shows a dot when something awaits approval or has failed.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        icon
            .task {
                model.openStudio = {
                    openWindow(id: WindowID.studio)
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                #if DEBUG
                if ProcessInfo.processInfo.environment["PROMO_STUDIO_PREVIEW_MENU"] == "1" {
                    openWindow(id: WindowID.menuPreview)
                }
                #endif
                // If launched at login, stay in the menu bar only; if opened manually, show the studio
                if !LaunchAtLogin.isEnabled || model.data.projects.isEmpty { model.openStudio() }
            }
    }

    private var needsAttention: Bool {
        model.isSetupIncomplete || model.data.posts.contains { post in
            post.status == .failed || (post.directed.map { !$0.produced && !$0.storyboard.scenes.isEmpty } ?? false && model.jobs[post.id] == nil)
        }
    }

    @ViewBuilder private var icon: some View {
        if !model.jobs.isEmpty {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse)
                .accessibilityLabel(Text("Promo Studio is working"))
        } else {
            Image(needsAttention ? "MenuBarIconBadge" : "MenuBarIcon")
                .accessibilityLabel(Text("Promo Studio"))
        }
    }
}
