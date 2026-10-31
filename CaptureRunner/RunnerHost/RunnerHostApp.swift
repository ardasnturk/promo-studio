import SwiftUI

/// Empty host app required by the UI test target. The app being captured is launched by bundle ID.
@main
struct RunnerHostApp: App {
    var body: some Scene {
        WindowGroup { Text("Promo Studio Capture Runner") }
    }
}
