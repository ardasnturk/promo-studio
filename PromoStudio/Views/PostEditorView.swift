import SwiftUI

/// Content studio: preview, scene editing, caption/hashtags and publishing/scheduling.
struct PostEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let postId: UUID
    /// Opens a new post created by actions such as translation
    var onOpenPost: ((UUID?) -> Void)?

    @State private var tab = 0
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var rewriteInstruction = ""

    var body: some View {
        if let post = model.post(postId), let project = model.project(post.projectId) {
            VStack(spacing: 0) {
                HStack {
                    Text(post.title).font(.title2.bold()).lineLimit(1)
                    StatusBadge(status: post.status)
                    Text(ContentLanguage.find(post.language).label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    if post.external == nil, post.directed == nil {
                    Menu("Copy in Another Language") {
                        ForEach(ContentLanguage.all.filter { $0.id != ContentLanguage.find(post.language).id }) { lang in
                            Button(lang.label) { onOpenPost?(model.translatePost(postId, to: lang.id)) }
                        }
                    }
                    .fixedSize()
                    .disabled(post.spec.scenes.isEmpty)
                    }
                    Button("Delete", role: .destructive) {
                        model.deletePost(postId)
                        dismiss()
                    }
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding()
                if let job = model.jobs[postId] {
                    JobBanner(job: job) { model.cancel(postId) }.padding(.horizontal)
                }
                if let err = post.lastError {
                    // Keep a long error message from pushing the title and buttons out of the window
                    ScrollView {
                        Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 44).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
                }
                HStack(alignment: .top, spacing: 16) {
                    preview(post)
                    VStack(spacing: 0) {
                        Picker("", selection: $tab) {
                            (post.directed != nil ? Text("Storyboard") : post.external == nil ? Text("Scenes") : Text("Template")).tag(0)
                            if post.external == nil { Text("Revise with Claude").tag(3) }
                            Text("Caption & SEO").tag(1)
                            Text("Publish").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.bottom, 8)
                        switch tab {
                        case 0:
                            if post.external != nil {
                                ExternalPanel(postId: postId)
                            } else if post.directed != nil {
                                StoryboardPanel(postId: postId, project: project)
                            } else {
                                ScenesEditor(postId: postId, project: project)
                            }
                        case 1: captionEditor(post)
                        case 3: RevisePanel(postId: postId)
                        default: publishPanel(post)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 1050, minHeight: 720)
            .onAppear { if post.brief != nil, post.directed == nil, post.videoFile == nil { tab = 3 } }
        } else {
            ContentUnavailableView("Content Deleted", systemImage: "trash").frame(width: 400, height: 300)
                .toolbar { Button("Close") { dismiss() } }
        }
    }

    // MARK: Preview

    private func preview(_ post: ContentPost) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black)
                if let url = model.videoURL(post), post.status != .rendering {
                    VideoPreview(url: url).clipShape(RoundedRectangle(cornerRadius: 16))
                } else if post.external != nil, model.jobs[postId] != nil {
                    VStack { ProgressView(); Text("Claude Code is producing the video…").foregroundStyle(.white.opacity(0.7)) }
                } else if let directed = post.directed, directed.storyboard.scenes.isEmpty {
                    VStack { ProgressView(); Text("Writing storyboard…").foregroundStyle(.white.opacity(0.7)) }
                } else if let directed = post.directed, model.jobs[postId] != nil, post.status != .rendering {
                    VStack(spacing: 8) {
                        ProgressView()
                        (directed.produced ? Text("Claude is working…") : Text("Preparing video…")).foregroundStyle(.white.opacity(0.7))
                    }
                } else if let directed = post.directed, !directed.produced {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack").font(.largeTitle)
                        Text("Waiting for storyboard approval").font(.headline)
                        Text("Review the storyboard and revise it if needed. When it’s ready, produce the video.")
                            .font(.caption).multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                } else if post.external == nil, post.spec.scenes.isEmpty {
                    VStack { ProgressView(); Text("Writing script…").foregroundStyle(.white.opacity(0.7)) }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "film").font(.largeTitle)
                        post.status == .rendering ? Text("Rendering…") : Text("Not rendered yet")
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 315, height: 560)
            HStack {
                if let directed = post.directed, !directed.produced {
                    Button {
                        model.produce(postId)
                    } label: {
                        Label("Approve and Produce Video", systemImage: "film.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(directed.storyboard.scenes.isEmpty || model.jobs[postId] != nil)
                    Button("Without Voiceover") { model.produce(postId, voiceover: false) }
                        .disabled(directed.storyboard.scenes.isEmpty || model.jobs[postId] != nil)
                        .help("Produce without voiceover (e.g. if the Gemini quota is used up); scene durations come from the storyboard")
                } else {
                Button {
                    model.render(postId)
                } label: {
                    Label {
                        post.videoFile == nil ? Text("Render") : Text("Re-render")
                    } icon: {
                        Image(systemName: "play.rectangle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRender(post) || model.jobs[postId] != nil)
                }
                if let url = model.videoURL(post) {
                    Button { saveVideo(url, title: post.title) } label: { Label("Save Video…", systemImage: "square.and.arrow.down") }
                        .labelStyle(.iconOnly).help("Save Video…")
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .labelStyle(.iconOnly).help("Share")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show in Finder", systemImage: "folder") }
                        .labelStyle(.iconOnly).help("Show in Finder")
                }
            }
            if post.isVideoOutdated {
                Label("The script has changed; this preview is from an older version. Render again.", systemImage: "exclamationmark.arrow.circlepath")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(width: 315)
            }
            Group {
                if let external = post.external {
                    Text(verbatim: "\(external.skill.map { "/" + $0 } ?? "") · \(external.compositionId ?? String(localized: "no composition"))")
                } else if let directed = post.directed {
                    let duration = Int(directed.storyboard.scenes.reduce(0) { $0 + $1.durationSec })
                    let sceneCount = directed.storyboard.scenes.count
                    Text("1080×1920 · ~\(duration) s · \(sceneCount) scenes · directed by Claude")
                } else {
                    Text("1080×1920 · ~\(Int(post.spec.totalDuration)) s · \(post.spec.theme.rawValue)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hasAccount(_ post: ContentPost) -> Bool {
        model.project(post.projectId).flatMap { model.account(for: $0) } != nil
    }

    private func canRender(_ post: ContentPost) -> Bool {
        if let directed = post.directed { return directed.produced }
        if let external = post.external { return external.compositionId != nil }
        return !post.spec.scenes.isEmpty
    }

    // MARK: Caption

    private func captionEditor(_ post: ContentPost) -> some View {
        let caption = Binding(get: { model.post(postId)?.caption ?? "" }, set: { v in model.updatePost(postId) { $0.caption = v } })
        let tags = Binding(
            get: { (model.post(postId)?.hashtags ?? []).map { "#\($0)" }.joined(separator: " ") },
            set: { v in
                model.updatePost(postId) {
                    $0.hashtags = v.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" })
                        .map { $0.replacingOccurrences(of: "#", with: "") }
                        .filter { !$0.isEmpty }
                }
            }
        )
        let alt = Binding(get: { model.post(postId)?.altText ?? "" }, set: { v in model.updatePost(postId) { $0.altText = v } })
        let total = post.fullCaption.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Caption").font(.headline)
                TextEditor(text: caption)
                    .font(.body)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text("The first 125 characters appear in the preview").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(total)/2200").font(.caption.monospacedDigit()).foregroundStyle(total > 2200 ? .red : .secondary)
                }
                Text("Hashtags (up to \(model.settings.maxHashtags))").font(.headline)
                TextField("#hashtag", text: tags)
                if post.hashtags.count > model.settings.maxHashtags {
                    Text("Too many hashtags.").font(.caption).foregroundStyle(.orange)
                }
                Text("Alt text (accessibility)").font(.headline)
                TextField("Describe the video", text: alt, axis: .vertical).lineLimit(2...4)
                if let tip = post.postingTip {
                    Label(tip, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                Text("Rewrite with Claude").font(.headline)
                HStack {
                    TextField("Optional direction (e.g. funnier, open with a question)", text: $rewriteInstruction)
                    Button("Rewrite") { model.rewriteCaption(postId, instruction: rewriteInstruction) }
                        .disabled(model.jobs[postId] != nil)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(post.fullCaption, forType: .string)
                } label: { Label("Copy Full Text", systemImage: "doc.on.doc") }
            }
        }
    }

    // MARK: Publishing

    /// Copies the rendered video to a user-chosen location (for sharing without connecting Instagram)
    private func saveVideo(_ url: URL, title: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        let name = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = (name.isEmpty ? "Promo Studio" : name) + ".mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            model.alert = error.localizedDescription
        }
    }

    private func publishPanel(_ post: ContentPost) -> some View {
        Form {
            Section("Account") {
                let project = model.project(post.projectId)
                if let published = model.account(post.accountId), post.status == .published {
                    LabeledContent("Published to", value: "@\(published.username)")
                } else if let project, let a = model.account(for: project) {
                    LabeledContent("Instagram", value: "@\(a.username)")
                    Text("Account for the “\(project.name)” project").font(.caption).foregroundStyle(.secondary)
                } else if !model.isConnected {
                    Text("No Instagram account is connected. Save the video and post it yourself, or connect an account in Account & Settings.")
                        .foregroundStyle(.secondary)
                    if let url = model.videoURL(post) {
                        Button("Save Video…") { saveVideo(url, title: post.title) }
                    }
                } else {
                    Label("“\(project?.name ?? "")” has no linked Instagram account. Choose one from the header of the project screen.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section("Publish Now") {
                Button {
                    model.queuePublish(postId)
                } label: { Label("Publish as Reel Now", systemImage: "paperplane.fill") }
                    .disabled(post.videoFile == nil || !hasAccount(post) || model.jobs[postId] != nil || post.status == .published)
            }
            Section("Schedule") {
                DatePicker("Publish time", selection: $scheduleDate, in: Date()...)
                HStack {
                    Button("Schedule") { model.schedule(postId, at: scheduleDate) }
                        .disabled(post.videoFile == nil || !hasAccount(post) || post.status == .published)
                    if post.status == .scheduled {
                        Button("Unschedule") { model.unschedule(postId) }
                    }
                }
                if let d = post.scheduledAt, post.status == .scheduled {
                    Label("Will be published on \(d.formatted(date: .complete, time: .shortened))", systemImage: "calendar.badge.clock")
                }
                Text("Scheduled posts are published while Promo Studio is open (running in the menu bar also works).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if post.status == .published {
                Section("Performance") {
                    if let link = post.permalink, let url = URL(string: link) {
                        Link("Open in Instagram", destination: url)
                    }
                    MetricsGrid(metrics: post.metrics)
                    Button("Refresh Stats") { model.refreshMetrics() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if let d = post.scheduledAt { scheduleDate = d } }
    }
}

struct MetricsGrid: View {
    let metrics: PostMetrics?

    var body: some View {
        if let m = metrics {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow { metric("Views", m.views); metric("Reach", m.reach); metric("Likes", m.likes) }
                GridRow { metric("Comments", m.comments); metric("Shares", m.shares); metric("Saves", m.saved) }
            }
            Text("Updated: \(m.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("No data yet").foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(value.map { $0.formatted() } ?? "–").font(.title3.monospacedDigit().bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Request, research findings, revisions with Claude and script versions
struct RevisePanel: View {
    @Environment(AppModel.self) private var model
    let postId: UUID

    @State private var instruction = ""
    @State private var renderAfter = true

    var body: some View {
        if let post = model.post(postId) {
            let busy = model.jobs[postId] != nil
            let locked = [.scheduled, .publishing, .published].contains(post.status)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let brief = post.brief {
                        GroupBox("Request") {
                            Text(brief.prompt).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        if let findings = brief.findings {
                            GroupBox("Research") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(findings).font(.callout).textSelection(.enabled)
                                    ForEach(brief.sources ?? [], id: \.self) { source in
                                        if let url = URL(string: source) {
                                            Link(Self.sourceLabel(url), destination: url).font(.caption).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if brief.research, !hasScript(post) {
                            Text("Claude is researching; findings and sources will appear here.").font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    Text("Give instructions").font(.headline)
                    TextField("e.g. Make the hook more aggressive, show the lineup prediction in scene 3, stress that it’s free in the CTA", text: $instruction, axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            if post.directed != nil {
                                model.reviseDirected(postId, instruction: instruction, renderAfter: renderAfter)
                            } else {
                                model.reviseScript(postId, instruction: instruction, renderAfter: renderAfter)
                            }
                            instruction = ""
                        } label: { Label("Revise", systemImage: "wand.and.stars") }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || locked || !hasScript(post) || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if post.directed?.produced != false {
                            Toggle("Render afterwards", isOn: $renderAfter)
                        }
                    }
                    Group {
                        if locked {
                            Text("Scheduled or published content can’t be revised. Unschedule it first.")
                        } else if let directed = post.directed {
                            if directed.produced {
                                Text("Claude updates the storyboard and the video’s code together; only the parts you ask for change. The video code from before each revision is kept.")
                            } else {
                                Text("The video hasn’t been produced yet: Claude updates the storyboard. When it’s ready, click “Approve and Produce Video” on the left.")
                            }
                        } else {
                            Text("Claude changes only the parts you ask for; you can also edit the scenes by hand. When you like the script, render it on the left.")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    if let revisions = post.revisions, !revisions.isEmpty {
                        Divider()
                        Text("Previous versions").font(.headline)
                        ForEach(revisions.reversed()) { r in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.callout.weight(.medium))
                                    Text("Next instruction: \(r.instruction)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    let date = r.createdAt.formatted(date: .abbreviated, time: .shortened)
                                    let sceneCount = r.storyboard?.scenes.count ?? r.scenes.count
                                    (r.code != nil ? Text("\(date) · \(sceneCount) scenes · video code") : Text("\(date) · \(sceneCount) scenes"))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("Restore This Version") { model.restoreRevision(postId, revisionId: r.id) }
                                    .controlSize(.small)
                                    .disabled(busy || locked)
                            }
                            .padding(8)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private func hasScript(_ post: ContentPost) -> Bool {
        if let directed = post.directed { return !directed.storyboard.scenes.isEmpty }
        return !post.spec.scenes.isEmpty
    }

    /// Short, distinguishable label such as "example.com › release-notes…"
    private static func sourceLabel(_ url: URL) -> String {
        let host = (url.host() ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        let last = url.pathComponents.last { $0 != "/" && !$0.isEmpty }
        return last.map { "\(host) › \($0)" } ?? host
    }
}

/// Scene list editor
struct ScenesEditor: View {
    @Environment(AppModel.self) private var model
    let postId: UUID
    let project: AppProject

    var body: some View {
        let spec = model.post(postId)?.spec
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Theme", selection: Binding(
                        get: { spec?.theme ?? .hype },
                        set: { v in model.updatePost(postId) { $0.spec.theme = v } }
                    )) {
                        ForEach(VideoTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(maxWidth: 320)
                    Spacer()
                    Menu("Add Scene") {
                        ForEach(VideoSpec.SceneKind.allCases, id: \.self) { kind in
                            Button(kind.label) {
                                model.updatePost(postId) { $0.spec.scenes.append(.init(kind: kind, title: String(localized: "New scene"), durationSec: 3)) }
                            }
                        }
                    }
                    .fixedSize()
                }
                Text("Writing *word* in a title paints that word in the accent color. If the voiceover text changes, the audio is regenerated and the scene duration is adjusted to match. Render again after making changes.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array((spec?.scenes ?? []).enumerated()), id: \.element.id) { index, _ in
                    SceneRow(postId: postId, index: index, project: project)
                }
            }
        }
    }
}

struct SceneRow: View {
    @Environment(AppModel.self) private var model
    let postId: UUID
    let index: Int
    let project: AppProject

    private func binding<T>(_ kp: WritableKeyPath<VideoSpec.Scene, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: {
                guard let scenes = model.post(postId)?.spec.scenes, scenes.indices.contains(index) else { return fallback }
                return scenes[index][keyPath: kp]
            },
            set: { v in
                model.updatePost(postId) { p in
                    guard p.spec.scenes.indices.contains(index) else { return }
                    p.spec.scenes[index][keyPath: kp] = v
                }
            }
        )
    }

    private func optional(_ kp: WritableKeyPath<VideoSpec.Scene, String?>) -> Binding<String> {
        let b = binding(kp, nil)
        return Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        let kind = binding(\.kind, .hook).wrappedValue
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                    Picker("", selection: binding(\.kind, .hook)) {
                        ForEach(VideoSpec.SceneKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                    let duration = binding(\.durationSec, 3).wrappedValue ?? 3
                    Stepper(
                        "\(duration, specifier: "%.1f") s",
                        value: Binding(get: { binding(\.durationSec, 3).wrappedValue ?? 3 }, set: { binding(\.durationSec, 3).wrappedValue = $0 }),
                        in: 1...10, step: 0.5
                    )
                    Spacer()
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { move(1) } label: { Image(systemName: "arrow.down") }
                    Button(role: .destructive) {
                        model.updatePost(postId) { p in if p.spec.scenes.indices.contains(index) { p.spec.scenes.remove(at: index) } }
                    } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.borderless)
                TextField("Title", text: binding(\.title, ""))
                TextField("Subtitle", text: optional(\.subtitle))
                TextField("Voiceover (starts with a tone tag like [excited])", text: optional(\.voiceover), axis: .vertical)
                    .lineLimit(1...3)
                if kind == .hook { TextField("Emoji", text: optional(\.emoji)).frame(width: 120) }
                if kind == .stat { TextField("Stat (e.g. 78%, 10K+)", text: optional(\.stat)) }
                if kind == .feature {
                    TextField("Bullet points (comma-separated)", text: Binding(
                        get: { (binding(\.bullets, nil).wrappedValue ?? []).joined(separator: ", ") },
                        set: { binding(\.bullets, nil).wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                }
                if kind == .screenshot || kind == .feature {
                    HStack {
                        Picker("Image", selection: optional(\.image)) {
                            Text("None").tag("")
                            ForEach(project.assets) { a in Text(a.label).tag(a.fileName) }
                        }
                        Picker("Style", selection: Binding(
                            get: { binding(\.imageStyle, nil).wrappedValue ?? .phone },
                            set: { binding(\.imageStyle, nil).wrappedValue = $0 }
                        )) {
                            Text("Phone frame").tag(VideoSpec.ImageStyle.phone)
                            Text("Raw (pre-framed image)").tag(VideoSpec.ImageStyle.raw)
                        }
                        .frame(width: 260)
                        if let img = binding(\.image, nil).wrappedValue {
                            LocalImage(url: Paths.projectAssets(project.id).appendingPathComponent(img), contentMode: .fit)
                                .frame(width: 34, height: 60)
                        }
                    }
                }
            }
        }
    }

    private func move(_ delta: Int) {
        model.updatePost(postId) { p in
            let target = index + delta
            guard p.spec.scenes.indices.contains(index), p.spec.scenes.indices.contains(target) else { return }
            p.spec.scenes.swapAt(index, target)
        }
    }
}

/// Details and parameters of a video generated from a library (e.g. sm-videos)
struct ExternalPanel: View {
    @Environment(AppModel.self) private var model
    let postId: UUID
    @State private var props = ""
    @State private var propsError: String?

    var body: some View {
        if let post = model.post(postId), let external = post.external {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("Library", value: model.library(external.libraryId)?.name ?? "—")
                            if let skill = external.skill { LabeledContent("Template", value: "/\(skill)") }
                            LabeledContent("Composition", value: external.compositionId ?? "—")
                            if !external.request.isEmpty {
                                Text("Request").font(.caption).foregroundStyle(.secondary)
                                Text(external.request).textSelection(.enabled)
                            }
                        }
                    }
                    if !external.summary.isEmpty {
                        Text("Claude Code summary").font(.headline)
                        Text(external.summary).font(.callout).textSelection(.enabled)
                    }
                    if !external.notes.isEmpty {
                        Text("Notes").font(.headline)
                        Text(external.notes).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !external.sources.isEmpty {
                        Text("Verification sources").font(.headline)
                        ForEach(external.sources, id: \.self) { s in
                            if let url = URL(string: s), url.scheme?.hasPrefix("http") == true { Link(s, destination: url).font(.caption) } else { Text(s).font(.caption) }
                        }
                    }
                    if external.compositionId != nil {
                        Divider()
                        Text("Parameters (props JSON)").font(.headline)
                        Text("You can edit the values and render again without changing code. Don’t change real facts (scores, dates) without verifying them.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $props)
                            .font(.caption.monospaced())
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        if let propsError { Text(propsError).font(.caption).foregroundStyle(.red) }
                        Button("Render Again with These Parameters") { save(render: true) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.jobs[postId] != nil)
                    }
                }
            }
            .onAppear { props = Self.pretty(external.propsJson) }
            .onChange(of: external.propsJson) { _, v in props = Self.pretty(v) }
        }
    }

    private func save(render: Bool) {
        let trimmed = props.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) is [String: Any] else {
                propsError = String(localized: "Not a valid JSON object.")
                return
            }
        }
        propsError = nil
        model.updatePost(postId) { $0.external?.propsJson = trimmed.isEmpty ? nil : trimmed }
        if render { model.render(postId) }
    }

    private static func pretty(_ json: String?) -> String {
        guard let json, let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else { return json ?? "" }
        return String(decoding: data, as: UTF8.self)
    }
}
