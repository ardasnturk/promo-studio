import SwiftUI

/// Settings: updates for Promo Studio and template libraries (GitHub Releases).
struct UpdatesSection: View {
    @Environment(AppModel.self) private var model
    @State private var checkingLibraries = false
    @State private var showTemplatesPrompt = false

    var body: some View {
        @Bindable var model = model
        let updater = model.updater
        Section {
            Toggle("Automatically check for updates", isOn: $model.settings.automaticallyChecksForUpdates)
            LabeledContent("Promo Studio", value: updater.currentVersion)
            switch updater.state {
            case .available(let release):
                HStack {
                    Label("New version: \(release.version.description)", systemImage: "arrow.down.app.fill")
                    Spacer()
                    Button("Release Notes") { updater.openReleasePage() }
                    Button("Install and Relaunch") { Task { await updater.installUpdate() } }
                        .buttonStyle(.borderedProminent)
                }
            case .downloading(let progress):
                ProgressView("Downloading…", value: progress)
            case .installing:
                HStack { ProgressView().controlSize(.small); Text("Installing…") }
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking…") }
            case .upToDate:
                Label("Promo Studio is up to date.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            case .idle:
                EmptyView()
            }
            if model.promoTemplates == nil {
                LabeledContent("Promo Templates") {
                    if model.jobs[AppModel.templatesJobId] != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Install…") { showTemplatesPrompt = true }
                    }
                }
            }
            ForEach(model.data.libraries) { lib in
                LabeledContent(lib.name) {
                    if TemplatesService.isMissing(lib) {
                        Label("Folder not found", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else if let latest = model.libraryUpdates[lib.id] {
                        Button("Update to \(latest)") { model.updateLibrary(lib.id) }
                            .disabled(model.jobs[lib.id] != nil)
                    } else {
                        Text(TemplatesService.packageInfo(lib).version?.description ?? "—").foregroundStyle(.secondary)
                    }
                }
            }
            Button("Check Now") {
                Task {
                    checkingLibraries = true
                    await updater.checkForUpdates(userInitiated: true)
                    await model.checkLibraryUpdates()
                    checkingLibraries = false
                }
            }
            .disabled(updater.isBusy || checkingLibraries)
        } header: {
            Text("Updates")
        } footer: {
            Text("New versions are checked on GitHub Releases once a day. Promo Studio updates are installed after being downloaded and having their signature verified; template libraries are updated with git if they have no local changes.")
        }
        .sheet(isPresented: $showTemplatesPrompt) {
            TemplatesPromptSheet { chooseExisting() }
        }
    }

    private func chooseExisting() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose Library")
        panel.message = String(localized: "Choose a folder containing Remotion video templates and Claude Code skills (e.g. promo-templates)")
        if panel.runModal() == .OK, let url = panel.url {
            _ = model.addLibrary(folder: url)
        }
    }
}
