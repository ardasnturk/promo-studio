import SwiftUI

/// External template library (e.g. Promo Templates): idea research, skill-based generation and composition list.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let libraryId: UUID
    var onRemoved: () -> Void

    @State private var focus = ""
    @State private var generate: GenerateRequest?
    @State private var openPost: UUID?

    var body: some View {
        if let lib = model.library(libraryId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(lib)
                    if let latest = model.libraryUpdates[libraryId], model.jobs[libraryId] == nil {
                        HStack {
                            Label("New version available: \(latest)", systemImage: "arrow.down.circle.fill").font(.headline)
                            Spacer()
                            Button("Update") { model.updateLibrary(libraryId) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(12)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let job = model.jobs[libraryId] {
                        JobBanner(job: job) { model.cancel(libraryId) }
                    }
                    ideasSection(lib)
                    skillsSection(lib)
                    compositionsSection(lib)
                    postsSection(lib)
                }
                .padding(24)
            }
            .brandWindowBackground()
            .navigationTitle(lib.name)
            .sheet(item: $generate) { req in
                GenerateSheet(request: req) { openPost = $0 }
            }
            .sheet(item: Binding(get: { openPost.map(PostRef.init) }, set: { openPost = $0?.id })) { ref in
                PostEditorView(postId: ref.id) { newId in openPost = newId }
            }
        } else {
            ContentUnavailableView("Library Not Found", systemImage: "books.vertical")
        }
    }

    private func header(_ lib: TemplateLibrary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lib.name).font(.largeTitle.bold())
                let versionPrefix = TemplatesService.packageInfo(lib).version.map { String(localized: "Version \($0.description) · ") } ?? ""
                Text("\(versionPrefix)\(lib.skills.count) skills · \(lib.compositions.count) compositions · Remotion: \(lib.remotionDir)")
                    .foregroundStyle(.secondary)
                Text(lib.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([lib.rootURL]) } label: { Label("Finder", systemImage: "folder") }
            Button { model.rescanLibrary(libraryId) } label: { Label("Rescan", systemImage: "arrow.clockwise") }
            Button("Remove", role: .destructive) {
                model.removeLibrary(libraryId)
                onRemoved()
            }
        }
    }

    private func ideasSection(_ lib: TemplateLibrary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find Ideas").font(.title2.bold())
            HStack {
                TextField("Focus (e.g. the app's name, campaign week, general)", text: $focus)
                Button("Research Trends") { model.generateIdeas(libraryId: libraryId, focus: focus) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.jobs[libraryId] != nil)
            }
            if let result = model.libraryIdeas[libraryId] {
                ForEach(result.ideas) { idea in
                    Card {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title).font(.headline)
                                Text("“\(idea.hook)”").font(.callout).foregroundStyle(.tint)
                                Text(idea.flow).font(.callout).foregroundStyle(.secondary)
                                Text(idea.why).font(.caption).foregroundStyle(.secondary)
                                Text("/\(idea.skill) · \(idea.difficulty)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Generate This") {
                                generate = GenerateRequest(libraryId: libraryId, skill: idea.skill, request: idea.request)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if !result.sources.isEmpty {
                    DisclosureGroup("Sources (\(result.sources.count))") {
                        ForEach(result.sources, id: \.self) { s in
                            if let url = URL(string: s) { Link(s, destination: url).font(.caption) } else { Text(s).font(.caption) }
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func skillsSection(_ lib: TemplateLibrary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Video Templates").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(lib.skills) { skill in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("/\(skill.name)").font(.headline.monospaced())
                            Text(skill.description).font(.callout).foregroundStyle(.secondary).lineLimit(5)
                            if !skill.argumentHint.isEmpty {
                                Text(skill.argumentHint).font(.caption).foregroundStyle(.tertiary)
                            }
                            Button("Generate…") { generate = GenerateRequest(libraryId: libraryId, skill: skill.name, request: "") }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func compositionsSection(_ lib: TemplateLibrary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compositions").font(.title2.bold())
            Text("Compositions with a schema can be re-rendered by editing their parameters in the studio, without changing any code.")
                .font(.caption).foregroundStyle(.secondary)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lib.compositions) { c in
                        HStack {
                            Text(c.folder).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            Text(c.id).font(.body.monospaced())
                            Spacer()
                            if c.hasSchema { Text("schema").font(.caption).padding(.horizontal, 6).background(.green.opacity(0.15), in: Capsule()) }
                        }
                    }
                }
            }
        }
    }

    private func postsSection(_ lib: TemplateLibrary) -> some View {
        let posts = model.data.posts.filter { $0.external?.libraryId == libraryId }.sorted { $0.createdAt > $1.createdAt }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Generated from This Library").font(.title2.bold())
            if posts.isEmpty { Text("No videos yet.").foregroundStyle(.secondary) }
            ForEach(posts) { post in
                Button { openPost = post.id } label: { PostRow(post: post, projectName: model.project(post.projectId)?.name) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct GenerateRequest: Identifiable {
    let id = UUID()
    let libraryId: UUID
    let skill: String
    let request: String
}

struct GenerateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: GenerateRequest
    var onCreated: (UUID) -> Void

    @State private var text = ""
    @State private var projectId: UUID?

    var body: some View {
        let skill = model.library(request.libraryId)?.skills.first { $0.name == request.skill }
        Form {
            Section("/\(request.skill)") {
                if let skill { Text(skill.description).font(.callout).foregroundStyle(.secondary) }
                TextField(skill?.argumentHint.isEmpty == false ? skill!.argumentHint : String(localized: "Request"), text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                Picker("Project / account", selection: $projectId) {
                    ForEach(model.data.projects) { Text($0.name).tag(Optional($0.id)) }
                }
            } footer: {
                Text("Claude Code runs the skill in this library in the background: it writes, validates, and renders the video (this may take a few minutes). New files are added to the library folder.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Generate with Claude Code") {
                    guard let projectId,
                          let id = model.generateFromSkill(libraryId: request.libraryId, skill: request.skill, request: text, projectId: projectId) else { return }
                    dismiss()
                    onCreated(id)
                }
                .disabled(projectId == nil)
            }
        }
        .onAppear {
            text = request.request
            projectId = model.suggestedProject(forSkill: request.skill) ?? model.data.projects.first?.id
        }
    }
}
