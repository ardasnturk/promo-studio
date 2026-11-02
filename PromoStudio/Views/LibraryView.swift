import SwiftUI

/// External template library (e.g. Promo Templates): idea research, skill-based generation and composition list.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let libraryId: UUID
    var onRemoved: () -> Void

    @State private var focus = ""
    @State private var generate: NewVideoRequest?
    @State private var newTemplate = false
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
                NewVideoSheet(request: req) { openPost = $0 }
            }
            .sheet(isPresented: $newTemplate) { NewTemplateSheet(libraryId: libraryId) }
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
                                generate = NewVideoRequest(template: TemplateRef(libraryId: libraryId, skill: idea.skill), prompt: idea.request)
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
            HStack {
                Text("Video Templates").font(.title2.bold())
                Spacer()
                Button { newTemplate = true } label: { Label("New Template…", systemImage: "wand.and.stars") }
                    .disabled(model.jobs[libraryId] != nil)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(lib.skills) { skill in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("/\(skill.name)").font(.headline.monospaced())
                            Text(skill.description).font(.callout).foregroundStyle(.secondary).lineLimit(5)
                            if !skill.argumentHint.isEmpty {
                                Text(skill.argumentHint).font(.caption).foregroundStyle(.tertiary)
                            }
                            Button("Generate…") { generate = NewVideoRequest(template: TemplateRef(libraryId: libraryId, skill: skill.name)) }
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

/// A new video template for the library, described in the user's own words; Claude Code writes the skill and its reference video.
struct NewTemplateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let libraryId: UUID
    @State private var prompt = ""

    var body: some View {
        Form {
            Section {
                TextField("Template", text: $prompt, prompt: Text("e.g. A wordless video where colored marbles race down a spiral track; the winner’s color is a guess for the comments."), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(5...12)
            } header: {
                Text("Describe the new template")
            } footer: {
                Text("Claude Code adds a new video template to the library: a skill and a reference composition, following the library’s rules. It checks the code and renders a test frame. Afterwards the template appears in the list and on the phone. This may take several minutes.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Template") {
                    model.createTemplate(libraryId: libraryId, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
