import AppKit
import Foundation
import Observation

/// State of a long-running job (analysis, render, posting).
struct JobState: Equatable {
    var message: String
    var progress: Double?
    var log: [String] = []
}

@MainActor
@Observable
final class AppModel {
    var data: AppData { didSet { DataStore.save(data); control?.dataChanged() } }
    var settings: AppSettings { didSet { settings.save(); control?.dataChanged() } }
    /// Key: project or post ID
    var jobs: [UUID: JobState] = [:] {
        didSet {
            guard let control else { return }
            for (id, job) in jobs where oldValue[id] != job { control.jobChanged(id, job) }
            for id in oldValue.keys where jobs[id] == nil { control.jobChanged(id, nil) }
        }
    }
    var setupJob: JobState?
    /// Setup checklist (nil: not checked yet)
    var requirements: [Requirement]?
    /// Checklist window (on launch if something is missing, or from the Help menu)
    var showSetup = false
    /// Post requested from the menu bar panel; the studio window shows it
    var requestedPost: UUID?
    /// Opens the studio window (the menu bar label sets it via `openWindow`)
    @ObservationIgnored var openStudio: () -> Void = {}
    var isSetupIncomplete: Bool { requirements?.contains { $0.isRequired && $0.status != .ready } ?? false }
    var alert: String? { didSet { if let alert, alert != oldValue { control?.alertShown(title: String(localized: "Something went wrong"), message: alert) } } }
    /// Non-error notice (e.g. accounts added)
    var notice: String? { didSet { if let notice, notice != oldValue { control?.alertShown(title: String(localized: "Info"), message: notice) } } }
    /// Local control API so Remote Code can drive the app from an iPhone
    @ObservationIgnored private var control: ControlServer?
    /// Promo Studio's own updates (GitHub Releases)
    @ObservationIgnored private(set) lazy var updater = AppUpdater { [weak self] in self?.settings.automaticallyChecksForUpdates ?? false }
    /// Library ID → newer version on GitHub
    var libraryUpdates: [UUID: String] = [:]
    /// Job ID of the Promo Templates install (progress is in `jobs`)
    static let templatesJobId = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
    /// Library ID → latest idea research (not persisted)
    var libraryIdeas: [UUID: ContentAI.IdeasResult] = [:]

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var schedulerTimer: Timer?
    private var activity: NSObjectProtocol?

    init() {
        data = DataStore.load()
        settings = AppSettings.load()
        // Reset jobs that were interrupted
        for i in data.posts.indices {
            if data.posts[i].status == .rendering { data.posts[i].status = .draft }
            if data.posts[i].status == .publishing { data.posts[i].status = .failed; data.posts[i].lastError = String(localized: "The app quit while publishing.") }
        }
        migrateAccounts()
        AudioService.preloadEnvKey()
        startScheduler()
        control = ControlServer(model: self)
        control?.start()
        updater.startAutomaticChecks()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(35))
            while !Task.isCancelled {
                guard let self else { return }
                if self.settings.automaticallyChecksForUpdates { await self.checkLibraryUpdates() }
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    // MARK: Template library install and updates

    /// Checks linked libraries for GitHub releases (based on the repository and version in package.json).
    func checkLibraryUpdates() async {
        for lib in data.libraries {
            let info = TemplatesService.packageInfo(lib)
            guard let repo = info.repository, let current = info.version,
                  let latest = try? await TemplatesService.latestVersion(of: repo) else { continue }
            libraryUpdates[lib.id] = latest > current ? latest.description : nil
        }
    }

    /// Installs Promo Templates into the `parent` folder and adds it as a library.
    func installTemplates(into parent: URL) {
        let jobId = Self.templatesJobId
        run(jobId, String(localized: "Installing Promo Templates…")) { [weak self] in
            let folder = try await TemplatesService.install(into: parent) { line in
                Task { @MainActor in self?.report(jobId, line) }
            }
            guard let self, self.addLibrary(folder: folder) != nil else { return }
            self.notice = String(localized: "Promo Templates installed: \(folder.path)")
        }
    }

    func updateLibrary(_ id: UUID) {
        guard let lib = library(id) else { return }
        run(id, String(localized: "Updating library…")) { [weak self] in
            try await TemplatesService.update(lib) { line in
                Task { @MainActor in self?.report(id, line) }
            }
            guard let self else { return }
            self.rescanLibrary(id)
            self.libraryUpdates[id] = nil
            self.notice = String(localized: "\(lib.name) updated.")
        }
    }

    // MARK: Access helpers

    func project(_ id: UUID) -> AppProject? { data.projects.first { $0.id == id } }
    func post(_ id: UUID) -> ContentPost? { data.posts.first { $0.id == id } }
    func posts(for projectId: UUID) -> [ContentPost] {
        data.posts.filter { $0.projectId == projectId }.sorted { $0.createdAt > $1.createdAt }
    }

    func updateProject(_ id: UUID, _ change: (inout AppProject) -> Void) {
        guard let i = data.projects.firstIndex(where: { $0.id == id }) else { return }
        change(&data.projects[i])
    }

    func updatePost(_ id: UUID, _ change: (inout ContentPost) -> Void) {
        guard let i = data.posts.firstIndex(where: { $0.id == id }) else { return }
        change(&data.posts[i])
    }

    /// Project analysis is produced in the default language, post texts in the post's language.
    func contentAI(language code: String? = nil) -> ContentAI {
        ContentAI(
            claude: ClaudeCode(model: settings.claudeModel),
            language: ContentLanguage.find(code ?? settings.contentLanguage).promptName,
            maxHashtags: settings.maxHashtags
        )
    }

    private func run(_ id: UUID, _ message: String, _ work: @escaping () async throws -> Void) {
        guard tasks[id] == nil else { return }
        jobs[id] = JobState(message: message)
        tasks[id] = Task {
            do {
                try await work()
            } catch is CancellationError {
            } catch {
                // A cancelled job (e.g. a stopped claude process) is not shown as an error
                if !Task.isCancelled { alert = Self.shortened(error.localizedDescription) }
            }
            jobs[id] = nil
            tasks[id] = nil
        }
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
    }

    private func report(_ id: UUID, _ message: String, progress: Double? = nil) {
        var j = jobs[id] ?? JobState(message: message)
        j.message = message
        if let progress { j.progress = progress }
        j.log.append(message)
        if j.log.count > 200 { j.log.removeFirst(j.log.count - 200) }
        jobs[id] = j
    }

    // MARK: Projects

    func addProject(folder: URL) -> UUID {
        if let existing = data.projects.first(where: { $0.folderPath == folder.path }) { return existing.id }
        let p = AppProject(name: folder.lastPathComponent.capitalized, folderPath: folder.path)
        data.projects.append(p)
        analyze(p.id)
        return p.id
    }

    func removeProject(_ id: UUID) {
        data.projects.removeAll { $0.id == id }
        data.posts.removeAll { $0.projectId == id && $0.status != .published }
        try? FileManager.default.removeItem(at: Paths.root.appendingPathComponent("projects/\(id.uuidString)"))
    }

    func analyze(_ id: UUID) {
        guard let project = project(id) else { return }
        let ai = contentAI()
        run(id, String(localized: "Scanning project…")) { [weak self] in
            let images = await Task.detached { ProjectScanner.findImages(in: project.folderURL) }.value
            self?.report(id, String(localized: "Claude Code is analyzing the project (\(images.count) candidate images)…"))
            let analysis = try await ai.analyze(project: project, images: images) { activity in
                Task { @MainActor in self?.report(id, activity) }
            }
            self?.updateProject(id) { p in
                p.analysis = analysis
                p.analyzedAt = Date()
                p.name = analysis.appName
                AssetService.importCandidates(analysis.screenshots, into: &p)
            }
        }
    }

    func captureSimulator(_ id: UUID, label: String) {
        Task {
            do {
                let asset = try await AssetService.captureSimulator(label: label, projectId: id)
                updateProject(id) { $0.assets.append(asset) }
            } catch {
                alert = error.localizedDescription
            }
        }
    }

    func importFiles(_ id: UUID, urls: [URL]) {
        updateProject(id) { AssetService.importFiles(urls, into: &$0) }
    }

    func removeAsset(_ asset: ProjectAsset, from id: UUID) {
        updateProject(id) { AssetService.remove(asset, from: &$0) }
    }

    // MARK: Content generation

    /// Writes a script with Claude, creates a draft post and optionally starts the render.
    /// If `brief` is given, the script follows the user's request (with web research if needed).
    func createPost(projectId: UUID, feature: AppFeature?, suggestion: ContentSuggestion?, theme: VideoTheme, seconds: Int, notes: String, autoRender: Bool, language: String? = nil, brief: PostBrief? = nil) -> UUID? {
        guard let analysis = project(projectId)?.analysis else { return nil }
        let language = ContentLanguage.find(language ?? settings.contentLanguage)
        let ai = contentAI(language: language.id)
        updateProject(projectId) { AssetService.ensureLocalizedAssets(language: language.id, in: &$0) }
        guard let project = self.project(projectId) else { return nil }
        var post = ContentPost(
            projectId: projectId,
            featureId: feature?.id,
            title: brief.map { String($0.prompt.prefix(60)) } ?? suggestion?.title ?? feature?.name ?? analysis.appName,
            language: language.id,
            spec: VideoSpec(
                theme: theme,
                brand: .init(appName: analysis.appName, primary: analysis.brandColors.primary, accent: analysis.brandColors.accent, background: analysis.brandColors.background, storeLabel: language.storeLabel),
                scenes: [],
                fps: 30,
                lang: language.id
            )
        )
        post.status = .draft
        post.brief = brief
        data.posts.append(post)
        let postId = post.id

        let message = brief?.research == true ? String(localized: "Claude is researching and writing the script…") : String(localized: "Claude is writing the script…")
        run(postId, message) { [weak self] in
            let script = try await ai.writeScript(project: project, languageCode: language.id, analysis: analysis, feature: feature, suggestion: suggestion, theme: theme, targetSeconds: seconds, extraNotes: notes, brief: brief) { activity in
                Task { @MainActor in self?.report(postId, activity) }
            }
            self?.updatePost(postId) { $0.apply(script) }
            if autoRender { try await self?.performRender(postId) }
        }
        return postId
    }

    /// Has Claude revise the script per an instruction; the previous version is added to the history.
    func reviseScript(_ postId: UUID, instruction: String, renderAfter: Bool) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, let post = post(postId), post.external == nil,
              let project = project(post.projectId), let analysis = project.analysis else { return }
        let ai = contentAI(language: post.language)
        let message = post.brief?.research == true ? String(localized: "Claude is revising (researching if needed)…") : String(localized: "Claude is revising the script…")
        run(postId, message) { [weak self] in
            let script = try await ai.reviseScript(post: post, project: project, analysis: analysis, instruction: instruction) { activity in
                Task { @MainActor in self?.report(postId, activity) }
            }
            guard let self, let latest = self.post(postId) else { return }
            self.updatePost(postId) { p in
                p.revisions = (p.revisions ?? []) + [latest.snapshot(instruction: instruction)]
                p.apply(script)
                p.markScriptChanged()
            }
            if renderAfter { try await self.performRender(postId) }
        }
    }

    /// Reverts to a script version from the history; the current version is also added to the history.
    func restoreRevision(_ postId: UUID, revisionId: UUID) {
        guard let post = post(postId), let revision = post.revisions?.first(where: { $0.id == revisionId }) else { return }
        let label = String(localized: "Restored the “\(revision.createdAt.formatted(date: .omitted, time: .shortened))” version")
        var code: String?
        if let id = post.directed?.compositionId {
            code = StudioService.snapshotCode(id, postId: postId)
            if let name = revision.code {
                do { try StudioService.restoreCode(name, id: id, postId: postId) } catch { alert = error.localizedDescription; return }
            }
        }
        updatePost(postId) { p in
            p.revisions = (p.revisions ?? []) + [post.snapshot(instruction: label, code: code)]
            p.title = revision.title
            p.spec.scenes = revision.scenes
            p.caption = revision.caption
            p.hashtags = revision.hashtags
            p.altText = revision.altText
            p.postingTip = revision.postingTip
            if let board = revision.storyboard {
                p.directed?.storyboard = board
                p.directed?.produced = revision.code != nil
            }
            p.markScriptChanged()
        }
    }

    // MARK: Claude-directed videos

    /// Has Claude write a storyboard from the user's request; the video is coded with `produce` once the storyboard is approved.
    func createDirectedPost(projectId: UUID, feature: AppFeature?, seconds: Int, language: String?, brief: PostBrief, voiceover: Bool) -> UUID? {
        guard let analysis = project(projectId)?.analysis else { return nil }
        let language = ContentLanguage.find(language ?? settings.contentLanguage)
        let ai = contentAI(language: language.id)
        updateProject(projectId) { AssetService.ensureLocalizedAssets(language: language.id, in: &$0) }
        guard let project = self.project(projectId) else { return nil }
        let kit = brandKit(for: project, copyAssets: false)
        var post = ContentPost(
            projectId: projectId,
            featureId: feature?.id,
            title: String(brief.prompt.prefix(60)),
            language: language.id,
            spec: VideoSpec(
                theme: settings.defaultTheme,
                brand: .init(appName: analysis.appName, primary: analysis.brandColors.primary, accent: analysis.brandColors.accent, background: analysis.brandColors.background, storeLabel: language.storeLabel),
                scenes: [],
                fps: StudioService.fps,
                lang: language.id
            )
        )
        post.brief = brief
        post.directed = DirectedVideo(storyboard: Storyboard(concept: "", scenes: []), compositionId: StudioService.compositionId(for: post.id))
        data.posts.append(post)
        let postId = post.id

        run(postId, brief.research ? String(localized: "Claude is researching and writing the storyboard…") : String(localized: "Claude is writing the storyboard…")) { [weak self] in
            let result = try await ai.writeStoryboard(project: project, languageCode: language.id, analysis: analysis, feature: feature, brief: brief, targetSeconds: seconds, voiceover: voiceover, brandKit: kit) { activity in
                Task { @MainActor in self?.report(postId, activity) }
            }
            self?.updatePost(postId) { $0.applyStoryboard(result) }
        }
        return postId
    }

    /// Generates the voiceover from the approved storyboard, has Claude code the video and renders it.
    /// `voiceover: false` produces without voiceover (e.g. when the Gemini quota is used up); scene durations come from the storyboard.
    func produce(_ postId: UUID, voiceover: Bool = true) {
        guard let post = post(postId), post.directed != nil, let project = project(post.projectId), let analysis = project.analysis else { return }
        let ai = contentAI(language: post.language)
        updatePost(postId) { $0.directed?.muted = !voiceover; $0.lastError = nil }
        run(postId, String(localized: "Preparing video…")) { [weak self] in
            guard let self else { return }
            try await self.recordingError(postId) {
                try await self.codeVideo(postId, project: project, analysis: analysis, ai: ai, revision: nil)
            }
            try await self.performRender(postId)
        }
    }

    /// Also write the error to the post so it stays visible in the studio after the alert closes.
    private func recordingError(_ postId: UUID, _ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            updatePost(postId) { $0.lastError = Self.shortened(error.localizedDescription) }
            throw error
        }
    }

    /// Truncates long error output (e.g. claude's stream-json dump) to a readable length.
    static func shortened(_ message: String, limit: Int = 600) -> String {
        message.count > limit ? String(message.prefix(limit)) + "…" : message
    }

    /// Revision by instruction: if the video is not coded yet only the storyboard is updated, otherwise storyboard + code.
    func reviseDirected(_ postId: UUID, instruction: String, renderAfter: Bool) {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, let post = post(postId), let directed = post.directed,
              let project = project(post.projectId), let analysis = project.analysis else { return }
        let ai = contentAI(language: post.language)
        let produced = directed.produced && StudioService.hasCode(directed.compositionId)
        run(postId, produced ? String(localized: "Claude is revising the storyboard and video…") : String(localized: "Claude is revising the storyboard…")) { [weak self] in
            guard let self else { return }
            let result = try await ai.reviseStoryboard(post: post, project: project, analysis: analysis, instruction: instruction, produced: produced) { activity in
                Task { @MainActor in self.report(postId, activity) }
            }
            let code = produced ? StudioService.snapshotCode(directed.compositionId, postId: postId) : nil
            guard let latest = self.post(postId) else { return }
            self.updatePost(postId) { p in
                p.revisions = (p.revisions ?? []) + [latest.snapshot(instruction: instruction, code: code)]
                p.applyStoryboard(result)
                p.markScriptChanged()
            }
            guard produced else { return }
            try await self.recordingError(postId) {
                try await self.codeVideo(postId, project: project, analysis: analysis, ai: ai, revision: instruction)
            }
            if renderAfter { try await self.performRender(postId) }
        }
    }

    /// Voiceover + props preparation and Claude writing/editing the code
    private func codeVideo(_ postId: UUID, project: AppProject, analysis: ProjectAnalysis, ai: ContentAI, revision: String?) async throws {
        try await RemotionService.prepare { [weak self] line in Task { @MainActor in self?.report(postId, line) } }
        guard var post = post(postId), let id = post.directed?.compositionId else { return }
        try await prepareDirectedAssets(&post, project: project)
        try StudioService.writeEntry(id)
        let kit = brandKit(for: project, copyAssets: true)
        report(postId, revision == nil ? String(localized: "Claude is coding the video…") : String(localized: "Claude is editing the video…"))
        let result = try await ai.produceVideo(post: post, analysis: analysis, brandKit: kit, revision: revision) { [weak self] activity in
            Task { @MainActor in self?.report(postId, activity) }
        }
        guard StudioService.hasCode(id) else { throw StudioError.noCode }
        updatePost(postId) {
            $0.directed?.produced = true
            $0.directed?.summary = result.summary
            $0.directed?.notes = result.notes
        }
    }

    /// Mirrors the storyboard into the spec, generates the voiceover and writes props.json.
    private func prepareDirectedAssets(_ post: inout ContentPost, project: AppProject) async throws {
        post.syncSpecFromStoryboard()
        if post.directed?.muted == true {
            for i in post.spec.scenes.indices { post.spec.scenes[i].audio = nil }
        } else {
            try await prepareAudio(&post, music: false)
        }
        let spec = post.spec
        updatePost(post.id) { $0.spec = spec }
        try StudioService.writeProps(post: post, project: project, storeLabel: ContentLanguage.find(post.language).storeLabel)
    }

    private func brandKit(for project: AppProject, copyAssets: Bool) -> ContentAI.BrandKit? {
        guard let (lib, folder) = StudioService.linkedLibrary(for: project, in: data.libraries) else { return nil }
        return ContentAI.BrandKit(
            libraryRoot: lib.rootURL,
            sourceFolder: lib.remotionURL.appendingPathComponent(folder),
            publicPath: copyAssets ? StudioService.importLibraryAssets(lib, project: project) : nil
        )
    }

    func render(_ postId: UUID) {
        guard post(postId) != nil else { return }
        run(postId, String(localized: "Preparing render…")) { [weak self] in
            try await self?.performRender(postId)
        }
    }

    private func performRender(_ postId: UUID) async throws {
        guard var post = post(postId), let project = project(post.projectId) else { return }
        updatePost(postId) { $0.status = .rendering; $0.lastError = nil }
        report(postId, String(localized: "Preparing render…"), progress: 0)
        do {
            let progress: @Sendable (Double, String) -> Void = { [weak self] progress, msg in
                Task { @MainActor in self?.report(postId, msg, progress: progress) }
            }
            let result: (video: String, cover: String)
            if post.directed != nil {
                try await prepareDirectedAssets(&post, project: project)
                result = try await StudioService.render(post: post, onProgress: progress)
            } else if let external = post.external {
                guard let lib = library(external.libraryId), let composition = external.compositionId else {
                    throw LibraryError.noVideo(String(localized: "Library or composition info is missing"))
                }
                result = try await LibraryService.render(lib, compositionId: composition, propsJson: external.propsJson, postId: postId, onProgress: progress)
            } else {
                try await prepareAudio(&post)
                result = try await RemotionService.render(post: post, project: project, onProgress: progress)
            }
            updatePost(postId) {
                $0.videoFile = result.video
                $0.coverFile = result.cover
                $0.status = .ready
            }
        } catch {
            updatePost(postId) { $0.status = .draft; $0.lastError = Self.shortened(error.localizedDescription) }
            throw error
        }
        if settings.autoPublishWhenReady {
            // run() won't start a new job while one with the same ID is running; post once the current job finishes
            Task { [weak self] in
                while self?.tasks[postId] != nil { try? await Task.sleep(for: .milliseconds(100)) }
                self?.queuePublish(postId)
            }
        }
    }

    /// Generates the voiceover (if needed), fits scene durations to the audio and writes the background beat.
    /// Persistent changes (audio files, durations) are saved to the post as well.
    private func prepareAudio(_ post: inout ContentPost, music: Bool = true) async throws {
        let postId = post.id
        let hasLines = post.spec.scenes.contains { !($0.voiceover ?? "").isEmpty }
        if settings.voiceoverEnabled, hasLines {
            if let key = AudioService.geminiKey() {
                try await AudioService.prepareVoiceover(post: &post, voice: settings.ttsVoice, model: settings.ttsModel, apiKey: key) { [weak self] msg in
                    Task { @MainActor in self?.report(postId, msg) }
                }
                let spec = post.spec, signature = post.voiceSignature
                updatePost(postId) { $0.spec = spec; $0.voiceSignature = signature }
            } else {
                report(postId, String(localized: "No Gemini key; voiceover skipped"))
                for i in post.spec.scenes.indices { post.spec.scenes[i].audio = nil }
            }
        } else {
            for i in post.spec.scenes.indices { post.spec.scenes[i].audio = nil }
        }

        if settings.musicEnabled, music {
            let fps = Double(post.spec.fps ?? 30)
            let frames = post.spec.scenes.map { max(27, ($0.durationSec ?? 3) * fps).rounded() }
            let starts = frames.indices.map { i in frames[..<i].reduce(0) { $0 + $1 - 12 } / fps }
            let total = post.spec.totalDuration
            let drop = starts.count > 1 ? starts[1] : min(2, total / 3)
            let hit = starts.last.map { $0 > 2 ? $0 : total - 1 } ?? total - 1
            try AudioService.writeBeat(seconds: total + 0.5, drop: drop, hit: hit, to: Paths.post(postId).appendingPathComponent("music.wav"))
            post.spec.music = "music.wav"
        } else {
            post.spec.music = nil
        }
    }

    func rewriteCaption(_ postId: UUID, instruction: String) {
        guard let post = post(postId), let project = project(post.projectId), let analysis = project.analysis else { return }
        let ai = contentAI(language: post.language)
        run(postId, String(localized: "Claude is rewriting the caption…")) { [weak self] in
            let r = try await ai.rewriteCaption(post: post, analysis: analysis, instruction: instruction, cwd: project.folderURL)
            self?.updatePost(postId) {
                $0.caption = r.caption
                $0.hashtags = r.hashtags.map { $0.replacingOccurrences(of: "#", with: "") }
                $0.altText = r.altText
            }
        }
    }

    /// Creates and renders a copy of the post adapted to another language. Returns the new post's ID.
    func translatePost(_ postId: UUID, to code: String) -> UUID? {
        guard let source = post(postId), source.external == nil, let analysis = project(source.projectId)?.analysis else { return nil }
        let language = ContentLanguage.find(code)
        updateProject(source.projectId) { AssetService.ensureLocalizedAssets(language: language.id, in: &$0) }
        guard let project = project(source.projectId) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.language = language.id
        copy.title = "\(source.title) (\(language.label))"
        copy.spec.lang = language.id
        copy.spec.brand.storeLabel = language.storeLabel
        for i in copy.spec.scenes.indices {
            copy.spec.scenes[i].id = UUID()
            copy.spec.scenes[i].audio = nil
        }
        copy.status = .draft
        copy.createdAt = Date()
        for keyPath in [\ContentPost.videoFile, \.coverFile, \.mediaId, \.permalink, \.lastError, \.voiceSignature, \.postingTip] {
            copy[keyPath: keyPath] = nil
        }
        copy.scheduledAt = nil
        copy.publishedAt = nil
        copy.metrics = nil
        data.posts.append(copy)
        let newId = copy.id
        let ai = contentAI(language: language.id)

        let usedImages = Set(source.spec.scenes.compactMap(\.image))
        run(newId, String(localized: "Claude is adapting it to \(language.label)…")) { [weak self] in
            var project = project
            // If there is a recipe, first capture from the simulator the screens used in the video that have no version in this language
            if project.captureRecipe != nil {
                do {
                    try await self?.performCapture(projectId: project.id, languages: [language.id], onlyAssets: usedImages, jobId: newId)
                } catch {
                    self?.report(newId, String(localized: "Simulator capture skipped: \(error.localizedDescription)"))
                }
                if let fresh = self?.project(project.id) { project = fresh }
                self?.report(newId, String(localized: "Claude is adapting it to \(language.label)…"))
            }
            let t = try await ai.translate(post: source, analysis: analysis, project: project, languageCode: language.id)
            let assets = Dictionary(project.assets.map { ($0.fileName, $0) }, uniquingKeysWith: { a, _ in a })
            self?.updatePost(newId) { p in
                p.title = t.title
                for (i, s) in t.scenes.enumerated() where p.spec.scenes.indices.contains(i) {
                    p.spec.scenes[i].title = s.title
                    p.spec.scenes[i].subtitle = s.subtitle.flatMap { $0.isEmpty ? nil : $0 }
                    p.spec.scenes[i].bullets = s.bullets.flatMap { $0.isEmpty ? nil : $0 }
                    p.spec.scenes[i].stat = s.stat.flatMap { $0.isEmpty ? nil : $0 }
                    p.spec.scenes[i].voiceover = s.voiceover.flatMap { $0.isEmpty ? nil : $0 }
                    if p.spec.scenes[i].image != nil, let img = s.image, let asset = assets[img] {
                        p.spec.scenes[i].image = img
                        p.spec.scenes[i].imageStyle = asset.isFramed ? .raw : .phone
                    }
                }
                p.caption = t.caption
                p.hashtags = t.hashtags.map { $0.replacingOccurrences(of: "#", with: "") }
                p.altText = t.altText
            }
            try await self?.performRender(newId)
        }
        return newId
    }

    // MARK: Template libraries

    func library(_ id: UUID) -> TemplateLibrary? { data.libraries.first { $0.id == id } }

    @discardableResult
    func addLibrary(folder: URL) -> UUID? {
        if let existing = data.libraries.first(where: { $0.path == folder.path }) { return existing.id }
        do {
            let lib = try LibraryService.scan(folder)
            data.libraries.append(lib)
            return lib.id
        } catch {
            alert = error.localizedDescription
            return nil
        }
    }

    func rescanLibrary(_ id: UUID) {
        guard let lib = library(id), let i = data.libraries.firstIndex(where: { $0.id == id }) else { return }
        do { data.libraries[i] = try LibraryService.scan(lib.rootURL, existing: lib) } catch { alert = error.localizedDescription }
    }

    func removeLibrary(_ id: UUID) {
        data.libraries.removeAll { $0.id == id }
    }

    /// The project the skill name starts with, if any (e.g. acme-promo → Acme)
    func suggestedProject(forSkill skill: String) -> UUID? {
        let prefix = skill.split(separator: "-").first.map { $0.lowercased() } ?? ""
        return data.projects.first { $0.name.lowercased().hasPrefix(prefix) || prefix.hasPrefix($0.name.lowercased()) }?.id
    }

    /// Produces a video with a library skill: Claude Code writes and renders the video inside the library,
    /// then Promo Studio imports it and has the caption written. Returns the new post's ID.
    func generateFromSkill(libraryId: UUID, skill: String, request: String, projectId: UUID) -> UUID? {
        guard let lib = library(libraryId), let project = project(projectId) else { return nil }
        let language = ContentLanguage.find(settings.contentLanguage)
        var post = ContentPost(
            projectId: projectId,
            title: request.isEmpty ? skill : String(request.prefix(70)),
            language: language.id,
            spec: VideoSpec(theme: settings.defaultTheme, brand: .init(appName: project.name, primary: "#000000", accent: "#FFFFFF", background: "#000000"), scenes: [], lang: language.id)
        )
        post.external = ExternalVideo(libraryId: libraryId, skill: skill, request: request, summary: "")
        post.status = .rendering
        data.posts.append(post)
        let postId = post.id
        let ai = contentAI(language: language.id)

        run(postId, String(localized: "\(lib.name): preparing \(skill)…")) { [weak self] in
            do {
                try await LibraryService.ensureInstalled(lib) { line in Task { @MainActor in self?.report(postId, line) } }
                self?.report(postId, String(localized: "Claude Code is running /\(skill)…"))
                let r = try await ai.runSkill(skill, request: request, library: lib) { activity in
                    Task { @MainActor in self?.report(postId, activity) }
                }
                self?.updatePost(postId) { p in
                    p.external?.compositionId = r.compositionId.flatMap { $0.isEmpty ? nil : $0 }
                    p.external?.propsJson = r.propsJson.flatMap { $0.isEmpty ? nil : $0 }
                    p.external?.summary = r.summary
                    p.external?.sources = r.sources ?? []
                    p.external?.notes = r.notes
                }
                guard r.status == "done", let path = r.videoPath, !path.isEmpty else {
                    self?.updatePost(postId) { $0.status = .draft; $0.lastError = r.status == "needs_input" ? String(localized: "Input needed: \(r.notes)") : String(localized: "Couldn't produce it: \(r.notes)") }
                    return
                }
                let files = try await LibraryService.importVideo(from: path, postId: postId)
                self?.updatePost(postId) { $0.videoFile = files.video; $0.coverFile = files.cover; $0.status = .ready }

                self?.report(postId, String(localized: "Claude is writing the caption…"))
                let caption = try await ai.captionForExternal(summary: r.summary, request: request, project: project, cwd: lib.rootURL)
                self?.updatePost(postId) { p in
                    p.title = caption.title
                    p.caption = caption.caption
                    p.hashtags = caption.hashtags.map { $0.replacingOccurrences(of: "#", with: "") }
                    p.altText = caption.altText
                }
            } catch {
                self?.updatePost(postId) { $0.status = $0.videoFile == nil ? .draft : .ready; $0.lastError = Self.shortened(error.localizedDescription) }
                throw error
            }
        }
        return postId
    }

    func generateIdeas(libraryId: UUID, focus: String) {
        guard let lib = library(libraryId) else { return }
        let ai = contentAI()
        run(libraryId, String(localized: "Claude is researching trends…")) { [weak self] in
            let ideas = try await ai.videoIdeas(focus: focus, library: lib) { activity in
                Task { @MainActor in self?.report(libraryId, activity) }
            }
            self?.libraryIdeas[libraryId] = ideas
        }
    }

    // MARK: Localized screens from the simulator

    /// Screens to find localized versions for: raw screens of unknown language from the repository or the simulator
    func localizableScreens(_ project: AppProject) -> [ProjectAsset] {
        project.assets.filter { $0.language == nil && $0.variantOf == nil && !$0.isFramed }
    }

    func createCaptureRecipe(_ projectId: UUID) {
        guard let project = project(projectId) else { return }
        let screens = localizableScreens(project)
        guard !screens.isEmpty else {
            alert = String(localized: "There are no raw screens to find localized versions of.")
            return
        }
        let ai = contentAI()
        run(projectId, String(localized: "Claude Code is working out the capture recipe…")) { [weak self] in
            let recipe = try await ai.captureRecipe(project: project, screens: screens) { activity in
                Task { @MainActor in self?.report(projectId, activity) }
            }
            self?.updateProject(projectId) { $0.captureRecipe = recipe }
        }
    }

    func captureLocalizedScreens(_ projectId: UUID, languages: [String]) {
        run(projectId, String(localized: "Preparing simulator…")) { [weak self] in
            try await self?.performCapture(projectId: projectId, languages: languages, onlyAssets: nil, jobId: projectId)
        }
    }

    /// Captures the recipe's screens in the given languages and adds them to the project as localized versions of the matching images.
    /// If `onlyAssets` is given, only those images missing a localized version are captured.
    func performCapture(projectId: UUID, languages: [String], onlyAssets: Set<String>?, jobId: UUID) async throws {
        guard let project = project(projectId), let recipe = project.captureRecipe else { return }
        let report: @Sendable (String) -> Void = { [weak self] msg in Task { @MainActor in self?.report(jobId, msg) } }

        var plan: [(String, [CaptureRecipe.Shot])] = []
        for lang in languages {
            let existing = Set(project.assets.filter { $0.language == lang }.compactMap(\.variantOf))
            let shots = recipe.shots.filter { shot in
                (onlyAssets?.contains(shot.assetFile) ?? true) && (onlyAssets == nil || !existing.contains(shot.assetFile))
            }
            if !shots.isEmpty { plan.append((lang, shots)) }
        }
        guard !plan.isEmpty else { return }

        let udid = try await SimulatorService.ensureDevice(onStatus: report)
        if await !SimulatorService.isInstalled(recipe.bundleId, on: udid) {
            try await SimulatorService.buildAndInstall(recipe, project: project, udid: udid, onLine: report)
        }
        let dir = Paths.projectAssets(projectId)
        for (lang, shots) in plan {
            let files = try await SimulatorService.capture(recipe, shots: shots, language: lang, udid: udid, into: dir, onStatus: report)
            let label = ContentLanguage.find(lang).label
            updateProject(projectId) { p in
                for shot in shots {
                    guard let file = files[shot.id] else { continue }
                    p.assets.removeAll { $0.variantOf == shot.assetFile && $0.language == lang }
                    p.assets.append(ProjectAsset(
                        fileName: file.lastPathComponent, label: "\(shot.label) (\(label))", source: .simulator,
                        isFramed: false, originalPath: nil, language: lang, variantOf: shot.assetFile
                    ))
                }
            }
        }
    }

    func deletePost(_ id: UUID) {
        cancel(id)
        if let compositionId = post(id)?.directed?.compositionId { StudioService.remove(postId: id, id: compositionId) }
        data.posts.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Paths.post(id))
    }

    func videoURL(_ post: ContentPost) -> URL? {
        post.videoFile.map { Paths.post(post.id).appendingPathComponent($0) }
    }

    func coverURL(_ post: ContentPost) -> URL? {
        post.coverFile.map { Paths.post(post.id).appendingPathComponent($0) }
    }

    // MARK: Posting and scheduling

    func schedule(_ postId: UUID, at date: Date) {
        updatePost(postId) { $0.scheduledAt = date; $0.status = .scheduled; $0.lastError = nil }
    }

    func unschedule(_ postId: UUID) {
        updatePost(postId) { $0.scheduledAt = nil; $0.status = .ready }
    }

    /// Posts to the Instagram account linked to the post's project. Projects without an account are not posted.
    func queuePublish(_ postId: UUID) {
        guard let post = post(postId), let video = videoURL(post), let project = project(post.projectId) else { return }
        guard let account = account(for: project), let token = token(for: account.userId) else {
            let message = String(localized: "No Instagram account is linked to “\(project.name)”. Choose an account on the project screen.")
            if post.status == .scheduled {
                updatePost(postId) { $0.status = .failed; $0.lastError = message }
            } else {
                alert = message
            }
            return
        }
        let client = api(token, mode: account.loginMode)
        updatePost(postId) { $0.status = .publishing; $0.lastError = nil; $0.accountId = account.userId }
        run(postId, String(localized: "Publishing to @\(account.username)…")) { [weak self] in
            do {
                let result = try await client.publishReel(userId: account.userId, videoURL: video, caption: post.fullCaption) { status in
                    Task { @MainActor in self?.report(postId, status) }
                }
                self?.updatePost(postId) {
                    $0.status = .published
                    $0.publishedAt = Date()
                    $0.mediaId = result.mediaId
                    $0.permalink = result.permalink
                }
            } catch {
                self?.updatePost(postId) { $0.status = .failed; $0.lastError = Self.shortened(error.localizedDescription) }
                throw error
            }
        }
    }

    private func startScheduler() {
        // Keep App Nap from delaying scheduled posts
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Scheduled posts")
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task { tick() }
    }

    private var lastMetricsRefresh = Date.distantPast

    private func tick() {
        let now = Date()
        for post in data.posts where post.status == .scheduled && (post.scheduledAt ?? .distantFuture) <= now && tasks[post.id] == nil {
            queuePublish(post.id)
        }
        if now.timeIntervalSince(lastMetricsRefresh) > 3600 {
            lastMetricsRefresh = now
            refreshMetrics()
            refreshTokenIfNeeded()
        }
    }

    // MARK: Instagram accounts

    var isConnected: Bool { !data.accounts.isEmpty }

    func account(_ id: String?) -> InstagramAccount? {
        id.flatMap { id in data.accounts.first { $0.userId == id } }
    }

    func account(for project: AppProject) -> InstagramAccount? { account(project.accountId) }

    func token(for accountId: String) -> String? { Keychain.get(Keychain.Key.instagramToken(accountId)) }

    func setAccount(_ accountId: String?, for projectId: UUID) {
        updateProject(projectId) { $0.accountId = accountId }
    }

    private func api(_ token: String, mode: InstagramLoginMode? = nil) -> InstagramAPI {
        InstagramAPI(graphVersion: settings.graphVersion, token: token, mode: mode ?? settings.loginMode)
    }

    private var appCredentials: (id: String, secret: String)? {
        let secret = Keychain.get(Keychain.Key.metaAppSecret) ?? ""
        guard !settings.metaAppId.isEmpty, !secret.isEmpty else { return nil }
        return (settings.metaAppId, secret)
    }

    /// Moves the single token from older versions into accounts and matches projects without an account by name.
    private func migrateAccounts() {
        if let legacy = Keychain.get(Keychain.Key.legacyInstagramToken) {
            for account in data.accounts where token(for: account.userId) == nil {
                Keychain.set(legacy, for: Keychain.Key.instagramToken(account.userId))
            }
            Keychain.set(nil, for: Keychain.Key.legacyInstagramToken)
        }
        for i in data.accounts.indices where data.accounts[i].loginMode == nil {
            data.accounts[i].loginMode = settings.loginMode
        }
        autoAssignAccounts()
    }

    /// Links projects without an account to an account whose username or name uniquely matches the project name.
    private func autoAssignAccounts() {
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        for project in data.projects where project.accountId == nil {
            let key = norm(project.name)
            guard key.count >= 3 else { continue }
            let matches = data.accounts.filter { a in
                [a.username, a.name ?? "", a.pageName ?? ""].map(norm).contains { $0.contains(key) || (!$0.isEmpty && key.contains($0)) }
            }
            if matches.count == 1 { setAccount(matches[0].userId, for: project.id) }
        }
    }

    func connect(withCode code: String) async {
        guard let app = appCredentials else {
            alert = InstagramError.missingConfig(String(localized: "Meta App ID and App Secret (Settings)")).localizedDescription
            return
        }
        do {
            let r = switch settings.loginMode {
            case .instagram:
                try await InstagramAPI.exchangeCode(code, appId: app.id, appSecret: app.secret, redirectURI: settings.redirectURI)
            case .facebook:
                try await InstagramAPI.exchangeFacebookCode(code, appId: app.id, appSecret: app.secret, redirectURI: settings.redirectURI, graphVersion: settings.graphVersion)
            }
            await connect(withToken: r.token, expiresIn: r.expiresIn, alreadyLongLived: true)
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Adds or updates every account the token can access. In Facebook mode a short-lived token
    /// is exchanged for a 60-day token if an App Secret is set.
    func connect(withToken token: String, expiresIn: Int? = nil, alreadyLongLived: Bool = false) async {
        var token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var expiresIn = expiresIn
        do {
            var warning: String?
            if settings.loginMode == .facebook, !alreadyLongLived {
                if let app = appCredentials {
                    do {
                        let long = try await InstagramAPI.facebookLongLived(token, appId: app.id, appSecret: app.secret, graphVersion: settings.graphVersion)
                        token = long.token
                        expiresIn = long.expiresIn
                    } catch {
                        warning = String(localized: "Connected, but the token couldn't be exchanged for a 60-day token (\(error.localizedDescription)). Check the App Secret and log in again; otherwise the connection will drop within a few hours.")
                    }
                } else {
                    warning = String(localized: "Connected, but without an App Secret the token is short-lived (a few hours). Enter the App Secret and log in again for a lasting connection.")
                }
                if warning != nil { expiresIn = expiresIn ?? 3600 }
            }
            let found = try await api(token).allAccounts()
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn ?? 5_184_000))
            var added: [String] = []
            for var account in found {
                account.tokenExpiresAt = expiry
                Keychain.set(token, for: Keychain.Key.instagramToken(account.userId))
                if let i = data.accounts.firstIndex(where: { $0.userId == account.userId }) {
                    data.accounts[i] = account
                } else {
                    data.accounts.append(account)
                    added.append("@\(account.username)")
                }
            }
            autoAssignAccounts()
            let addedText = added.isEmpty ? nil : String(localized: "Accounts added: \(added.joined(separator: ", ")).")
            if let warning {
                alert = [addedText, warning].compactMap { $0 }.joined(separator: "\n\n")
            } else if let addedText {
                notice = addedText
            }
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Groups of accounts sharing the same token (with Facebook Login one token manages several accounts)
    private func tokenGroups() -> [(token: String, accounts: [InstagramAccount])] {
        var groups: [String: [InstagramAccount]] = [:]
        for account in data.accounts {
            if let t = token(for: account.userId) { groups[t, default: []].append(account) }
        }
        return groups.map { ($0.key, $0.value) }
    }

    private func storeToken(_ token: String, expiresIn: Int, for accounts: [InstagramAccount]) {
        for account in accounts {
            Keychain.set(token, for: Keychain.Key.instagramToken(account.userId))
            if let i = data.accounts.firstIndex(where: { $0.userId == account.userId }) {
                data.accounts[i].tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            }
        }
    }

    /// Extends short-lived Facebook tokens to 60 days once a valid App Secret is entered, without logging in again.
    func upgradeTokenIfNeeded() async {
        guard let app = appCredentials else { return }
        for group in tokenGroups() {
            guard group.accounts.contains(where: { ($0.loginMode ?? settings.loginMode) == .facebook }),
                  group.accounts.contains(where: { ($0.tokenExpiresAt ?? .distantPast).timeIntervalSinceNow < 7 * 86400 }) else { continue }
            do {
                let long = try await InstagramAPI.facebookLongLived(group.token, appId: app.id, appSecret: app.secret, graphVersion: settings.graphVersion)
                storeToken(long.token, expiresIn: long.expiresIn, for: group.accounts)
            } catch {
                alert = String(localized: "Couldn't extend the token: \(error.localizedDescription)")
            }
        }
    }

    func disconnect(_ accountId: String) {
        Keychain.set(nil, for: Keychain.Key.instagramToken(accountId))
        data.accounts.removeAll { $0.userId == accountId }
        for project in data.projects where project.accountId == accountId { setAccount(nil, for: project.id) }
    }

    /// Refreshes saved accounts; also adds accounts the token can newly access (e.g. a Page linked later).
    func refreshAccounts() async {
        var added: [String] = []
        for group in tokenGroups() {
            let mode = group.accounts.first?.loginMode
            guard let found = try? await api(group.token, mode: mode).allAccounts() else { continue }
            for var fresh in found {
                if let i = data.accounts.firstIndex(where: { $0.userId == fresh.userId }) {
                    fresh.tokenExpiresAt = data.accounts[i].tokenExpiresAt
                    fresh.loginMode = data.accounts[i].loginMode
                    data.accounts[i] = fresh
                } else {
                    fresh.tokenExpiresAt = group.accounts.first?.tokenExpiresAt
                    fresh.loginMode = mode
                    Keychain.set(group.token, for: Keychain.Key.instagramToken(fresh.userId))
                    data.accounts.append(fresh)
                    added.append("@\(fresh.username)")
                }
            }
        }
        guard !added.isEmpty else { return }
        autoAssignAccounts()
        notice = String(localized: "Accounts added: \(added.joined(separator: ", ")).")
    }

    private func refreshTokenIfNeeded() {
        let app = appCredentials
        let version = settings.graphVersion
        for group in tokenGroups() {
            guard group.accounts.contains(where: { ($0.tokenExpiresAt ?? .distantFuture).timeIntervalSinceNow < 7 * 86400 }) else { continue }
            let mode = group.accounts.first?.loginMode ?? settings.loginMode
            let client = api(group.token, mode: mode)
            let token = group.token
            Task {
                let refreshed: (token: String, expiresIn: Int)? = switch mode {
                case .instagram: try? await client.refreshToken()
                case .facebook: try? await app.asyncMap { try await InstagramAPI.facebookLongLived(token, appId: $0.id, appSecret: $0.secret, graphVersion: version) }
                }
                if let r = refreshed { storeToken(r.token, expiresIn: r.expiresIn, for: group.accounts) }
            }
        }
    }

    /// Fetches insights for posted posts with the token of the account they were posted to.
    func refreshMetrics() {
        let targets: [(UUID, String, InstagramAPI)] = data.posts.compactMap { post in
            guard post.status == .published, let mediaId = post.mediaId,
                  let accountId = post.accountId ?? project(post.projectId)?.accountId,
                  let token = token(for: accountId) else { return nil }
            return (post.id, mediaId, api(token, mode: account(accountId)?.loginMode))
        }
        Task {
            for (postId, mediaId, client) in targets {
                if let m = try? await client.mediaMetrics(mediaId) {
                    updatePost(postId) { $0.metrics = m }
                }
            }
        }
    }

    // MARK: Setup

    func prepareRemotion() {
        guard setupJob == nil else { return }
        setupJob = JobState(message: String(localized: "Setting up Remotion…"))
        Task {
            do {
                try await RemotionService.prepare { line in
                    Task { @MainActor in self.setupJob?.message = line }
                }
            } catch {
                alert = error.localizedDescription
            }
            setupJob = nil
            await refreshRequirements()
        }
    }

    func refreshRequirements() async {
        requirements = await SetupService.check(
            hasGeminiKey: AudioService.geminiKey() != nil,
            isConnected: isConnected,
            hasLibrary: !data.libraries.isEmpty
        )
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
