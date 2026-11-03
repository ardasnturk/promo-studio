import SwiftUI

/// A failure on a post: what happened, the fix as a button, and the raw output behind a disclosure.
struct ProblemBanner: View {
    let problem: Problem
    /// A job is running for the post (the fix would start another)
    var busy = false
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.title).font(.callout.weight(.semibold))
                    Text(problem.message).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if problem.details != nil {
                    Button(showDetails ? "Hide Details" : "Details") { showDetails.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
                if let fix = problem.fix {
                    FixButton(fix: fix, problem: problem).disabled(busy)
                }
            }
            if showDetails, let details = problem.details {
                ScrollView {
                    Text(details).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Runs a failure's fix: the model retries or repairs; settings, setup and login open here.
struct FixButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let fix: Problem.Fix
    let problem: Problem

    var body: some View {
        Button(Self.label(fix)) {
            switch fix {
            case .reconnect, .settings: SettingsWindow.show(using: openSettings)
            case .setup: model.showSetup = true
            case .retry, .repair, .withoutVoiceover: model.apply(fix, to: problem)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    static func label(_ fix: Problem.Fix) -> LocalizedStringKey {
        switch fix {
        case .retry: "Try Again"
        case .repair: "Let Claude Fix It"
        case .withoutVoiceover: "Produce Without Voiceover"
        case .reconnect: "Reconnect Account"
        case .settings: "Open Settings"
        case .setup: "Open Setup"
        }
    }

    /// Whether the fix can run from where the problem is shown (a retry needs the post it belongs to)
    static func isAvailable(_ fix: Problem.Fix, for problem: Problem) -> Bool {
        [.reconnect, .settings, .setup].contains(fix) || problem.subject != nil
    }
}
