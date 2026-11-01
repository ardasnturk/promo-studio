import SwiftUI

/// Suggests installing Promo Templates when it isn't linked.
struct TemplatesPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// For picking an already downloaded library
    var onChooseExisting: () -> Void
    @State private var dontShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Install Promo Templates").font(.title2.bold())
                    Text("Promo Studio's template library").foregroundStyle(.secondary)
                }
            }
            Text("Promo Templates contains ready-made video formats such as physics loops, puzzles, and textless videos, along with the Claude Code skills that produce them. Promo Studio uses this library for idea research, skill-based generation, and the brand kit in promo films.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Setup downloads the repository from GitHub into the folder you choose (git) and installs the Remotion skills and npm dependencies. It may take a few minutes; Node.js and git are required.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let job = model.jobs[AppModel.templatesJobId] {
                JobBanner(job: job) { model.cancel(AppModel.templatesJobId) }
            }
            Link("View on GitHub", destination: TemplatesService.pageURL).font(.callout)
            Toggle("Don't show again", isOn: $dontShowAgain)
            HStack {
                Button("Later") { close() }
                Spacer()
                Button("Already Downloaded? Choose Folder…") {
                    close()
                    onChooseExisting()
                }
                Button("Install…") { install() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.jobs[AppModel.templatesJobId] != nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: model.promoTemplates != nil) { _, linked in if linked { dismiss() } }
    }

    private func close() {
        if dontShowAgain { model.settings.templatesPromptDismissed = true }
        dismiss()
    }

    private func install() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Install Here")
        panel.message = String(localized: "Choose the folder to download Promo Templates into (a promo-templates folder is created inside it)")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.installTemplates(into: url)
    }
}
