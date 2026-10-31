import XCTest

/// Promo Studio's simulator capture tool. Reads the job from the JSON file in the PROMO_STUDIO_JOB environment variable
/// (passed to xcodebuild as TEST_RUNNER_PROMO_STUDIO_JOB) and writes each screen's PNG to the `output` path.
final class CaptureTests: XCTestCase {
    struct Job: Decodable {
        var bundleId: String
        var shots: [Shot]
    }

    struct Shot: Decodable {
        var id: String
        var launchArguments: [String]
        var url: String
        var taps: [String]
        var waitSeconds: Double
        var output: String
    }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCapture() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["PROMO_STUDIO_JOB"], "PROMO_STUDIO_JOB yok")
        let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for shot in job.shots {
            let app = XCUIApplication(bundleIdentifier: job.bundleId)
            app.terminate()
            app.launchArguments = shot.launchArguments
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            sleep(2)

            if !shot.url.isEmpty, let url = URL(string: shot.url) {
                app.open(url)
                acceptSystemAlert(springboard)
                sleep(1)
            }
            for target in shot.taps {
                tap(target, in: app)
                acceptSystemAlert(springboard)
            }
            Thread.sleep(forTimeInterval: max(1, shot.waitSeconds))
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try png.write(to: URL(fileURLWithPath: shot.output))
            print("AUTOMAT_SHOT_DONE \(shot.id)")
        }
    }

    /// Taps the default (right-hand) button on system alerts such as "Open in …?".
    private func acceptSystemAlert(_ springboard: XCUIApplication) {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        let buttons = alert.buttons
        if buttons.count > 0 { buttons.element(boundBy: buttons.count - 1).tap() }
    }

    /// Finds an element by accessibility identifier, then by visible text, and taps it.
    private func tap(_ target: String, in app: XCUIApplication) {
        let byId = app.descendants(matching: .any).matching(identifier: target).firstMatch
        if byId.waitForExistence(timeout: 5), byId.isHittable {
            byId.tap()
        } else {
            let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", target)).firstMatch
            if byLabel.waitForExistence(timeout: 3) { byLabel.tap() } else { print("AUTOMAT_TAP_MISSING \(target)") }
        }
        sleep(1)
    }
}
