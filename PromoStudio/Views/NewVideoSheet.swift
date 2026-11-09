import SwiftUI
import UniformTypeIdentifiers

/// A library video template (skill) picked for a new video.
struct TemplateRef: Hashable {
    let libraryId: UUID
    let skill: String
}

struct NewVideoRequest: Identifiable {
    let id = UUID()
    var template: TemplateRef?
    var prompt = ""
}

/// New video that doesn't have to belong to a project: from a prompt (directed by Claude) or from a library template.
/// A project and an Instagram account are both optional and independent of each other.
struct NewVideoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: NewVideoRequest
    var onCreated: (UUID) -> Void

    @State private var prompt = ""
    @State private var template: TemplateRef?
    @State private var projectId: UUID?
    @State private var accountId = ""
    @State private var promo = false
    @State private var language = "tr"
    @State private var seconds = 20
    @State private var voiceover = true
    @State private var research = true
    @State private var format = PostFormat.video
    @State private var size = ImageSize.portrait
    @State private var slides = 1
    /// Images for Claude to look at and use
    @State private var images: [URL] = []
    @State private var pickingImages = false
    /// Make it later instead of now
    @State private var planned = false
    @State private var runAt = Date().addingTimeInterval(3600)
    @State private var autoApprove = false
    @State private var autoPublish = false
    @State private var story = false

    var body: some View {
        let skill = template.flatMap { t in model.library(t.libraryId)?.skills.first { $0.name == t.skill } }
        let project = model.project(projectId)
        Form {
            Section {
                Picker("Make", selection: $format) {
                    Text("Video").tag(PostFormat.video)
                    Text("Image").tag(PostFormat.image)
                }
                .pickerStyle(.segmented)
                .onChange(of: format) { if format == .image { template = nil } }
            }
            Section {
                TextField("Request", text: $prompt, prompt: Text(skill.flatMap { $0.argumentHint.isEmpty ? nil : $0.argumentHint } ?? String(localized: "e.g. Tonight’s derby in 20 seconds: the key stats, the lineups and a prediction.")), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(4...10)
                if format == .video {
                Picker("Template", selection: $template) {
                    Text("None: Claude directs it from scratch").tag(TemplateRef?.none)
                    ForEach(model.data.libraries) { lib in
                        Section(lib.name) {
                            ForEach(Self.videoSkills(lib)) { s in
                                Text(verbatim: "/\(s.name)").tag(Optional(TemplateRef(libraryId: lib.id, skill: s.name)))
                            }
                        }
                    }
                }
                if let skill { Text(skill.description).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                format == .image ? Text("What should the image show?") : Text("What should the video be about?")
            } footer: {
                if format == .image {
                    Text("Claude first writes a design brief. Nothing is rendered until you approve it.")
                } else if template != nil {
                    Text("Claude Code runs the template in the library in the background: it writes, checks and renders the video. This may take a few minutes.")
                } else {
                    Text("Claude first writes a scene-by-scene storyboard. Nothing is rendered until you approve it.")
                }
            }
            Section {
                Picker("Project", selection: $projectId) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.data.projects.filter { $0.analysis != nil || template != nil }) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Instagram account", selection: $accountId) {
                    if let a = project.flatMap({ model.account(for: $0) }) {
                        Text("Project’s account (@\(a.username))").tag("")
                    } else {
                        Text("None").tag("")
                    }
                    ForEach(model.data.accounts) { Text(verbatim: "@\($0.username)").tag($0.userId) }
                }
            } footer: {
                Text("Both are optional. Without a project the video isn’t about any app; without an account you can save the video and post it yourself.")
            }
            if template == nil {
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(images, id: \.self) { url in
                                    LocalImage(url: url)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button { images.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                                .buttonStyle(.plain).foregroundStyle(.white, .black.opacity(0.6)).padding(3)
                                        }
                                }
                            }
                        }
                    }
                    Button { pickingImages = true } label: { Label("Add Images…", systemImage: "photo.badge.plus") }
                } header: {
                    Text("Your Images")
                } footer: {
                    Text("Optional. Claude looks at them and builds the \(format == .image ? String(localized: "image") : String(localized: "video")) around them; people and objects in them are also cut out of their background.")
                }
                .fileImporter(isPresented: $pickingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                    if case let .success(urls) = result { images += urls.filter { !images.contains($0) } }
                }
            }
            if template == nil, format == .image {
                Section("Image") {
                    Picker("Size", selection: $size) {
                        ForEach(ImageSize.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Stepper(value: $slides, in: 1...10) {
                        slides == 1 ? Text("Single image") : Text("Carousel: \(slides) slides")
                    }
                    Picker("Language", selection: $language) {
                        ForEach(ContentLanguage.all) { Text($0.label).tag($0.id) }
                    }
                    Toggle("Let Claude research the web", isOn: $research)
                }
            } else if template == nil {
                Section("Video") {
                    if projectId != nil {
                        Picker("Video type", selection: $promo) {
                            Text("Free-form video").tag(false)
                            Text("Promo film for the app").tag(true)
                        }
                    }
                    Picker("Language", selection: $language) {
                        ForEach(ContentLanguage.all) { Text($0.label).tag($0.id) }
                    }
                    Stepper("Duration: \(seconds) s", value: $seconds, in: 10...60, step: 1)
                    Toggle("Voiceover", isOn: $voiceover)
                    Toggle("Let Claude research the web", isOn: $research)
                }
            }
            planSection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(planned ? "Plan" : template == nil ? (format == .image ? "Write Design" : "Write Storyboard") : "Generate with Claude Code") { create() }
                    .disabled((template == nil && trimmed.isEmpty && images.isEmpty) || (planned && runAt <= .now))
            }
        }
        .onAppear {
            prompt = request.prompt
            template = request.template
            language = model.settings.contentLanguage
            voiceover = model.settings.voiceoverEnabled
        }
    }

    private var trimmed: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var hasAccount: Bool {
        model.account(accountId.isEmpty ? nil : accountId) != nil || model.project(projectId).flatMap { model.account(for: $0) } != nil
            || (format != .image && model.channel(model.settings.youtubeDefaultChannel) != nil)
    }

    @ViewBuilder private var planSection: some View {
        Section {
            Toggle("Make it later", isOn: $planned)
            if planned {
                DatePicker("Start at", selection: $runAt, in: Date()...)
                if template == nil {
                    Toggle(format == .image ? "Approve the design automatically" : "Approve the storyboard automatically", isOn: $autoApprove)
                }
                Toggle("Post automatically when it’s ready", isOn: $autoPublish)
                    .disabled(!hasAccount)
                if autoPublish, hasAccount, !(format == .image && size == .story) {
                    Picker("Share as", selection: $story) {
                        (format == .image ? (slides > 1 ? Text("Carousel") : Text("Post")) : Text("Reel")).tag(false)
                        Text("Story").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
        } footer: {
            if planned {
                PlanFootnote(needsAccount: !hasAccount, autoPublish: autoPublish, autoApprove: autoApprove || template != nil)
            }
        }
    }

    /// Templates that make a video (an idea-research skill doesn't)
    static func videoSkills(_ lib: TemplateLibrary) -> [LibrarySkill] {
        lib.skills.filter { !$0.name.contains("idea") && !$0.name.contains("fikir") }
    }

    private func create() {
        let account = accountId.isEmpty ? nil : accountId
        let id: UUID?
        let publish = autoPublish && hasAccount
        let plan = planned ? CreationPlan(runAt: runAt, autoApprove: autoApprove && template == nil, autoPublish: publish) : nil
        if let template {
            id = model.generateFromSkill(libraryId: template.libraryId, skill: template.skill, request: trimmed, projectId: projectId, accountId: account, plan: plan)
        } else {
            // Security-scoped files from the open panel are read now; the post keeps its own copies
            let uploads = images.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try? Data(contentsOf: url)
            }
            let request = trimmed.isEmpty ? String(localized: "Make it from my images.") : trimmed
            id = model.createDirectedPost(
                projectId: projectId, feature: nil, seconds: seconds, language: language,
                brief: PostBrief(prompt: request, research: research), voiceover: voiceover && format == .video,
                style: promo ? .promo : .freeform, accountId: account,
                image: format == .image ? size : nil, slides: slides, uploads: uploads, plan: plan
            )
        }
        guard let id else { return }
        if planned, publish, story { model.setPlacement(.story, forPost: id) }
        dismiss()
        onCreated(id)
    }
}

/// Videos that belong to no project, and the starting point for a new prompt or template video.
struct VideosView: View {
    @Environment(AppModel.self) private var model
    @State private var newVideo: NewVideoRequest?
    @State private var openPost: UUID?

    var body: some View {
        let posts = model.data.posts.filter { $0.projectId == nil }.sorted { $0.createdAt > $1.createdAt }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Videos").font(.largeTitle.bold())
                        Text("Make a video from a prompt or a template, without a project. Pick a project or an Instagram account only if you want to.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { newVideo = NewVideoRequest() } label: { Label("New Video…", systemImage: "plus") }
                        .buttonStyle(GradientButtonStyle(fullWidth: false))
                        .fixedSize()
                }
                if posts.isEmpty {
                    ContentUnavailableView("No videos yet", systemImage: "film.stack", description: Text("Videos you make without a project appear here."))
                }
                ForEach(posts) { post in
                    Button { openPost = post.id } label: { PostRow(post: post) }
                        .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .brandWindowBackground()
        .navigationTitle(Text("Videos"))
        .sheet(item: $newVideo) { req in
            NewVideoSheet(request: req) { openPost = $0 }
        }
        .sheet(item: Binding(get: { openPost.map(PostRef.init) }, set: { openPost = $0?.id })) { ref in
            PostEditorView(postId: ref.id) { newId in openPost = newId }
        }
    }
}
