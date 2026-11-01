import SwiftUI

enum SidebarItem: Hashable {
    case project(UUID)
    case library(UUID)
    case queue
    case analytics
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var selection: SidebarItem? = .queue
    @State private var showTemplatesPrompt = false
    /// "Install Promo Templates" was chosen from the checklist; the prompt opens once the list closes
    @State private var templatesAfterSetup = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $selection) {
                if model.isSetupIncomplete {
                    Section {
                        Button {
                            model.showSetup = true
                        } label: {
                            sidebarLabel("Finish Setup", symbol: "exclamationmark.triangle.fill", colors: [.orange, .red])
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Planning") {
                    sidebarLabel("Posting Calendar", symbol: "calendar", colors: [Brand.indigo, Brand.violet])
                        .tag(SidebarItem.queue)
                    sidebarLabel("Analytics", symbol: "chart.bar.xaxis", colors: [.green, Brand.teal])
                        .tag(SidebarItem.analytics)
                }
                Section("Projects") {
                    ForEach(model.data.projects) { project in
                        HStack(spacing: 8) {
                            projectIcon(project)
                            Text(project.name)
                            Spacer()
                            if model.jobs[project.id] != nil { ProgressView().controlSize(.small) }
                        }
                        .padding(.vertical, 2)
                        .tag(SidebarItem.project(project.id))
                        .contextMenu {
                            Button("Remove Project", role: .destructive) {
                                if selection == .project(project.id) { selection = .queue }
                                model.removeProject(project.id)
                            }
                        }
                    }
                    Button {
                        addProject()
                    } label: {
                        Label("Add Project Folder…", systemImage: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Section("Templates") {
                    ForEach(model.data.libraries) { lib in
                        HStack(spacing: 8) {
                            IconBadge(symbol: "books.vertical.fill", colors: [Brand.violet, Brand.pink])
                            Text(lib.name)
                            Spacer()
                            if model.jobs[lib.id] != nil { ProgressView().controlSize(.small) }
                            if model.libraryUpdates[lib.id] != nil {
                                Circle().fill(Brand.pink).frame(width: 7, height: 7).help("Update available")
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(SidebarItem.library(lib.id))
                    }
                    if model.promoTemplates == nil {
                        Button {
                            showTemplatesPrompt = true
                        } label: {
                            HStack {
                                Label("Install Promo Templates…", systemImage: "arrow.down.circle")
                                if model.jobs[AppModel.templatesJobId] != nil { ProgressView().controlSize(.small) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button {
                        addLibrary()
                    } label: {
                        Label("Add Library…", systemImage: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { accountFooter }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            switch selection {
            case let .project(id):
                ProjectDetailView(projectId: id).id(id)
            case let .library(id):
                LibraryView(libraryId: id) { selection = .queue }.id(id)
            case .analytics:
                AnalyticsView()
            default:
                QueueView()
            }
        }
        .sheet(isPresented: $showTemplatesPrompt) {
            TemplatesPromptSheet { addLibrary() }
        }
        .sheet(isPresented: $model.showSetup, onDismiss: {
            if templatesAfterSetup {
                templatesAfterSetup = false
                showTemplatesPrompt = true
            }
        }) {
            SetupSheet {
                SettingsWindow.show(using: openSettings)
            } onInstallTemplates: {
                templatesAfterSetup = true
            }
        }
        .sheet(item: Binding(get: { model.requestedPost.map(PostRef.init) }, set: { model.requestedPost = $0?.id })) { ref in
            PostEditorView(postId: ref.id) { newId in model.requestedPost = newId }
        }
        .task {
            await model.refreshRequirements()
            // If a required tool is missing, show the checklist first; otherwise suggest installing the template library
            // (until the user chooses "don't show again")
            if model.isSetupIncomplete {
                model.showSetup = true
            } else if model.promoTemplates == nil, !model.settings.templatesPromptDismissed {
                showTemplatesPrompt = true
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert ?? "")
        }
        .alert("Info", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private func sidebarLabel(_ title: LocalizedStringKey, symbol: String, colors: [Color]) -> some View {
        Label {
            Text(title)
        } icon: {
            IconBadge(symbol: symbol, colors: colors)
        }
        .padding(.vertical, 2)
    }

    /// Project logo, or the name's initial if there is none
    private func projectIcon(_ project: AppProject) -> some View {
        ZStack {
            if let logo = project.logoFile {
                LocalImage(url: Paths.projectAssets(project.id).appendingPathComponent(logo))
            } else {
                IconBadge(symbol: "app.fill", colors: [Brand.indigo, Brand.violet])
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22 * 0.26, style: .continuous))
    }

    /// Sidebar footer: Instagram accounts, updates and Settings
    private var accountFooter: some View {
        VStack(spacing: 6) {
            if let release = model.updater.availableRelease {
                Button {
                    SettingsWindow.show(using: openSettings)
                } label: {
                    Label("Promo Studio \(release.version.description) Is Available", systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.teal)
            }
            Button {
                SettingsWindow.show(using: openSettings)
            } label: {
                HStack(spacing: 8) {
                    IconBadge(symbol: "camera.fill", colors: [Brand.violet, Brand.pink])
                    Text(accountsLabel).lineLimit(1)
                    Spacer()
                    Circle().fill(model.isConnected ? .green : .orange).frame(width: 7, height: 7)
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Account & Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var accountsLabel: String {
        switch model.data.accounts.count {
        case 0: String(localized: "Connect Instagram")
        case 1: "@\(model.data.accounts[0].username)"
        default: String(localized: "\(model.data.accounts.count) Instagram accounts")
        }
    }

    private func addLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose Library")
        panel.message = String(localized: "Choose a folder containing Remotion video templates and Claude Code skills (e.g. promo-templates)")
        if panel.runModal() == .OK, let url = panel.url, let id = model.addLibrary(folder: url) {
            selection = .library(id)
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Choose Project")
        panel.message = String(localized: "Choose the source code folder of the app you want to post about")
        if panel.runModal() == .OK, let url = panel.url {
            selection = .project(model.addProject(folder: url))
        }
    }
}
