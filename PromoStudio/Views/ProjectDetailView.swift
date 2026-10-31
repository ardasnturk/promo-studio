import SwiftUI
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let projectId: UUID

    @State private var composer: ComposerRequest?
    @State private var openPost: UUID?
    @State private var simLabel = ""
    @State private var showLocalScreens = false

    var body: some View {
        if let project = model.project(projectId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(project)
                    if let job = model.jobs[projectId] {
                        JobBanner(job: job) { model.cancel(projectId) }
                        if project.analysis == nil { activityLog(job) }
                    }
                    if let a = project.analysis {
                        overview(a)
                        promptSection(project)
                        featuresSection(project, a)
                        suggestionsSection(project, a)
                    }
                    assetsSection(project)
                    postsSection(project)
                }
                .padding(24)
            }
            .brandWindowBackground()
            .navigationTitle(project.name)
            .sheet(isPresented: $showLocalScreens) {
                LocalScreensSheet(projectId: projectId)
            }
            .sheet(item: $composer) { req in
                ComposerSheet(request: req) { postId in openPost = postId }
            }
            .sheet(item: Binding(get: { openPost.map(PostRef.init) }, set: { openPost = $0?.id })) { ref in
                PostEditorView(postId: ref.id) { newId in openPost = newId }
            }
        } else {
            ContentUnavailableView("Project Not Found", systemImage: "questionmark.folder")
        }
    }

    // MARK: Sections

    private func header(_ p: AppProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                LocalImage(url: p.logoFile.map { Paths.projectAssets(p.id).appendingPathComponent($0) })
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.largeTitle.weight(.bold))
                    if let a = p.analysis { Text(a.tagline).font(.title3).opacity(0.9).lineLimit(2) }
                }
                Spacer()
                let count = model.posts(for: p.id).filter { [.ready, .scheduled, .published].contains($0.status) }.count
                StatusPill(text: Text("\(count) videos"), color: .green, onGradient: true)
            }
            .foregroundStyle(.white)
            HStack(spacing: 8) {
                Picker(selection: Binding(get: { p.accountId }, set: { model.setAccount($0, for: p.id) })) {
                    Text("No account selected").tag(String?.none)
                    ForEach(model.data.accounts) { Text("@\($0.username)").tag(Optional($0.userId)) }
                } label: {
                    Image(systemName: "camera.circle")
                }
                .frame(width: 200)
                .help("The Instagram account this project's content is posted to")
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([p.folderURL])
                } label: { Label("Finder", systemImage: "folder") }
                Button {
                    showLocalScreens = true
                } label: { Label("Localized Screens…", systemImage: "globe") }
                    .disabled(p.analysis == nil)
                Button {
                    model.analyze(p.id)
                } label: {
                    Label(p.analysis == nil ? String(localized: "Analyze") : String(localized: "Reanalyze"), systemImage: "wand.and.stars")
                }
                .disabled(model.jobs[p.id] != nil)
            }
            .controlSize(.regular)
        }
        .padding(18)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func activityLog(_ job: JobState) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code is working").font(.headline)
                ForEach(Array(job.log.suffix(8).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func overview(_ a: ProjectAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(a.summary)
                HStack(spacing: 24) {
                    labeled("Category", a.category)
                    labeled("Target audience", a.targetAudience)
                    labeled("Tone", a.tone)
                    labeled("Platform", a.platforms.joined(separator: ", "))
                    Spacer()
                    HStack(spacing: 6) {
                        ColorSwatch(hex: a.brandColors.primary)
                        ColorSwatch(hex: a.brandColors.accent)
                        ColorSwatch(hex: a.brandColors.background)
                    }
                }
            }
        }
    }

    private func labeled(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).lineLimit(2)
        }
    }

    private func promptSection(_ p: AppProject) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(symbol: "sparkles", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video from Your Own Request").font(.headline)
                    Text("Describe what you want; Claude researches it and writes the script. Nothing is rendered until you approve it, and you can revise it step by step.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Write Prompt…") {
                    composer = ComposerRequest(projectId: p.id, featureId: nil, suggestionId: nil, custom: true)
                }
                .buttonStyle(GradientButtonStyle(fullWidth: false))
            }
        }
    }

    private func featuresSection(_ p: AppProject, _ a: ProjectAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which feature do you want to highlight?").font(.title2.weight(.bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(a.features) { f in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(f.emoji) \(f.name)").font(.headline)
                            Text(f.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            if let hook = f.hooks.first {
                                Text("“\(hook)”").font(.caption.italic()).foregroundStyle(.tint)
                            }
                            HStack {
                                Button("Quick Video") {
                                    let id = model.createPost(projectId: p.id, feature: f, suggestion: nil, theme: model.settings.defaultTheme, seconds: 15, notes: "", autoRender: true)
                                    openPost = id
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Customize…") {
                                    composer = ComposerRequest(projectId: p.id, featureId: f.id, suggestionId: nil)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func suggestionsSection(_ p: AppProject, _ a: ProjectAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Content Ideas").font(.title2.weight(.bold))
            ForEach(a.suggestions) { s in
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.headline)
                            Text(s.angle).font(.callout).foregroundStyle(.secondary)
                            Text("Hook: “\(s.hook)”").font(.caption).foregroundStyle(.tint)
                            Text("Theme: \(s.theme.label)").font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Button("Generate in One Click") {
                                let feature = a.features.first { $0.id == s.featureId }
                                openPost = model.createPost(projectId: p.id, feature: feature, suggestion: s, theme: s.theme, seconds: 15, notes: "", autoRender: true)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Customize…") {
                                composer = ComposerRequest(projectId: p.id, featureId: s.featureId, suggestionId: s.id)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func assetsSection(_ p: AppProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Screenshots").font(.title2.weight(.bold))
                Text("\(p.assets.count)").foregroundStyle(.secondary)
                Spacer()
                TextField("Label (e.g. AI prediction screen)", text: $simLabel).frame(width: 220)
                Button {
                    model.captureSimulator(p.id, label: simLabel)
                    simLabel = ""
                } label: { Label("Capture from Simulator", systemImage: "iphone.gen3") }
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.allowedContentTypes = [.png, .jpeg, .webP]
                    if panel.runModal() == .OK { model.importFiles(p.id, urls: panel.urls) }
                } label: { Label("Add Images", systemImage: "photo.badge.plus") }
            }
            if p.assets.isEmpty {
                Text("No images yet. Analysis collects screenshots from the repository automatically; you can also capture them from the Simulator or drag and drop them here.")
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(p.assets) { asset in
                        VStack(spacing: 4) {
                            LocalImage(url: AssetService.url(of: asset, in: p), contentMode: .fit)
                                .frame(width: 120, height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    if let lang = asset.language {
                                        Text(lang.uppercased())
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(.black.opacity(0.6), in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                            Text(asset.label).font(.caption).lineLimit(2).frame(width: 120)
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) { model.removeAsset(asset, from: p.id) }
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.importFiles(p.id, urls: [url]) } }
                    }
                }
                return true
            }
        }
    }

    private func postsSection(_ p: AppProject) -> some View {
        let posts = model.posts(for: p.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text("This Project's Content").font(.title2.weight(.bold))
            if posts.isEmpty {
                Text("No content yet.").foregroundStyle(.secondary)
            }
            ForEach(posts) { post in
                Button { openPost = post.id } label: { PostRow(post: post) }.buttonStyle(.plain)
            }
        }
    }
}

struct PostRef: Identifiable { let id: UUID }

struct PostRow: View {
    @Environment(AppModel.self) private var model
    let post: ContentPost
    var projectName: String?

    var body: some View {
        Card {
            HStack(spacing: 12) {
                LocalImage(url: model.coverURL(post))
                    .frame(width: 54, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(post.title).font(.headline)
                        if let projectName { Text(projectName).font(.caption).foregroundStyle(.secondary) }
                        Text((post.language ?? "tr").uppercased()).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(post.caption.split(separator: "\n").first.map(String.init) ?? String(localized: "Waiting for script…"))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    if let date = post.scheduledAt, post.status == .scheduled {
                        Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock").font(.caption)
                    }
                    if let err = post.lastError { Text(err).font(.caption).foregroundStyle(.red).lineLimit(2) }
                }
                Spacer()
                if let job = model.jobs[post.id] {
                    VStack(alignment: .trailing) {
                        if let p = job.progress { ProgressView(value: p).frame(width: 100) } else { ProgressView().controlSize(.small) }
                        Text(job.message).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 200, alignment: .trailing)
                    }
                }
                StatusBadge(status: post.status)
            }
        }
        .contentShape(Rectangle())
    }
}
