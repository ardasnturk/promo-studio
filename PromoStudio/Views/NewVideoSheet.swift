import SwiftUI

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

    var body: some View {
        let skill = template.flatMap { t in model.library(t.libraryId)?.skills.first { $0.name == t.skill } }
        let project = model.project(projectId)
        Form {
            Section {
                TextField("Request", text: $prompt, prompt: Text(skill.flatMap { $0.argumentHint.isEmpty ? nil : $0.argumentHint } ?? String(localized: "e.g. Tonight’s derby in 20 seconds: the key stats, the lineups and a prediction.")), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(4...10)
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
            } header: {
                Text("What should the video be about?")
            } footer: {
                if template != nil {
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
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(template == nil ? "Write Storyboard" : "Generate with Claude Code") { create() }
                    .disabled(template == nil && trimmed.isEmpty)
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

    /// Templates that make a video (an idea-research skill doesn't)
    static func videoSkills(_ lib: TemplateLibrary) -> [LibrarySkill] {
        lib.skills.filter { !$0.name.contains("idea") && !$0.name.contains("fikir") }
    }

    private func create() {
        let account = accountId.isEmpty ? nil : accountId
        let id: UUID?
        if let template {
            id = model.generateFromSkill(libraryId: template.libraryId, skill: template.skill, request: trimmed, projectId: projectId, accountId: account)
        } else {
            id = model.createDirectedPost(
                projectId: projectId, feature: nil, seconds: seconds, language: language,
                brief: PostBrief(prompt: trimmed, research: research), voiceover: voiceover,
                style: promo ? .promo : .freeform, accountId: account
            )
        }
        guard let id else { return }
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
