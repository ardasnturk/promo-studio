import Foundation

/// Prompts and JSON schemas sent to Claude Code.
struct ContentAI {
    var claude: ClaudeCode
    var language: String
    var maxHashtags: Int

    // MARK: 1) Project analysis

    func analyze(project: AppProject, images: [ProjectScanner.ImageInfo], onActivity: @escaping @Sendable (String) -> Void) async throws -> ProjectAnalysis {
        let imageList = images.map { "- \($0.relativePath) (\($0.width)x\($0.height))" }.joined(separator: "\n")
        let prompt = """
        You are a mobile app marketing expert and Instagram Reels strategist. The folder you are in contains the source code of an app called "\(project.name)".

        Task: Understand the app by examining the code (README, CLAUDE.md/AGENTS.md, docs, screen/route files, theme/color files, store metadata, the fastlane folder) and produce an analysis for creating social media content.

        Rules:
        - All texts must be written in \(language).
        - features: 4-8 user-facing features that can be highlighted in a video. id is short kebab-case. hooks: for each feature, 2-3 curiosity-sparking hook sentences usable in the first 2 seconds of a Reels.
        - suggestions: 4-6 content ideas. Try different angles (problem/solution, "did you know", comparison, trend, real-life use case). theme field: hype | showcase | neon | minimal.
        - brandColors: extract the real brand colors from the theme/color definitions in the code as #RRGGBB. background must be dark and suitable for video.
        - screenshots: From the list below, pick at most 12 images that best show the app's interface (path relative to the project root, exactly as in the list). Do not pick irrelevant images such as App Store Connect/admin panels that are not in-app screens. Of copies of the same screen in different languages/devices, take only one (preferably \(language) or English, phone size). isFramed: true if the image is already a framed store image / has marketing text on it, false if it is a raw screenshot. label: what is on the screen.
        - logoPath: relative path of a square image usable as the app logo/icon (leave empty if you cannot find one).
        - storeURL: if there is an App Store or Play Store link in the code/metadata.
        - Do not make up information; do not use numbers/claims you are not sure about.

        Candidate images:
        \(imageList.isEmpty ? "(none found)" : imageList)
        """
        return try await claude.structured(
            ProjectAnalysis.self,
            prompt: prompt,
            schema: Self.analysisSchema,
            cwd: project.folderURL,
            tools: ["Read", "Glob", "Grep", "Bash(ls:*)", "Bash(find:*)", "Bash(cat:*)", "Bash(head:*)"],
            maxTurns: 40,
            onActivity: onActivity
        )
    }

    // MARK: 2) Video script + caption

    struct ScriptResult: Decodable {
        var title: String
        var scenes: [VideoSpec.Scene]
        var caption: String
        var hashtags: [String]
        var altText: String
        var postingTip: String
        /// Only for research-backed (prompt-based) generation
        var findings: String?
        var sources: [String]?
    }

    func writeScript(
        project: AppProject,
        languageCode: String,
        analysis: ProjectAnalysis,
        feature: AppFeature?,
        suggestion: ContentSuggestion?,
        theme: VideoTheme,
        targetSeconds: Int,
        extraNotes: String,
        brief: PostBrief? = nil,
        onActivity: @escaping @Sendable (String) -> Void
    ) async throws -> ScriptResult {
        let usable = Self.assets(for: languageCode, in: project)
        let research = brief?.research ?? false
        let task = brief.map { b in
            """
            Write a \(targetSeconds)-second vertical (9:16) Reels for the Instagram account of the app below. The USER'S REQUEST determines the topic and purpose of the video; the app information is there so you use the brand, features and screenshots correctly. The video will be rendered automatically with Remotion in the "\(theme.rawValue)" theme.

            USER'S REQUEST
            \(b.prompt)
            """
        } ?? """
            Write the script for a \(targetSeconds)-second vertical (9:16) promotional Reels for the app below. The video will be rendered automatically with Remotion in the "\(theme.rawValue)" theme.
            """
        let prompt = """
        You are a content director who produces viral Instagram Reels. \(task)

        APP
        \(Self.compact(analysis))

        \(feature.map { "FEATURE TO HIGHLIGHT\n\($0.emoji) \($0.name): \($0.summary) — Why it matters: \($0.whyItMatters). Hook ideas: \($0.hooks.joined(separator: " | "))" } ?? (brief == nil ? "FEATURE TO HIGHLIGHT\nGeneral app introduction" : "Choose the app feature(s) that best fit the request yourself."))

        \(suggestion.map { "CONTENT IDEA: \($0.title) — Angle: \($0.angle). Hook: \($0.hook)" } ?? "")
        \(extraNotes.isEmpty ? "" : "ADDITIONAL NOTES: \(extraNotes)")
        \(research ? Self.researchRules : "")

        AVAILABLE SCREENSHOTS (use the file name exactly as given in the image field):
        \(usable.isEmpty ? "(none — do not use screenshot scenes)" : Self.assetList(usable))

        \(rules(targetSeconds: targetSeconds, research: research))
        """
        return try await claude.structured(
            ScriptResult.self,
            prompt: prompt,
            schema: Self.scriptSchema(assetNames: usable.map(\.fileName), maxHashtags: maxHashtags, research: research),
            cwd: project.folderURL,
            tools: research ? Self.researchTools : [],
            maxTurns: research ? 40 : 4,
            onActivity: onActivity
        )
    }

    /// Updates the existing script per the user's instruction; parts not mentioned are kept.
    func reviseScript(post: ContentPost, project: AppProject, analysis: ProjectAnalysis, instruction: String, onActivity: @escaping @Sendable (String) -> Void) async throws -> ScriptResult {
        let languageCode = post.language ?? "tr"
        let usable = Self.assets(for: languageCode, in: project)
        let research = post.brief?.research ?? false
        let current = Self.scriptJSON(post)
        let prompt = """
        You are a content director who produces viral Instagram Reels. Update the Reels script below according to the user's REVISION INSTRUCTION. The video will be rendered with Remotion in the "\(post.spec.theme.rawValue)" theme.

        REVISION INSTRUCTION
        \(instruction)

        - Change only what the instruction requires; leave the scenes, texts, caption and hashtags the instruction does not touch exactly as they are.
        - If the instruction requires new information, \(research ? "research and verify it" : "rely on the app information and the project files; do not make anything up")
        - If the instruction conflicts with the rules (e.g. duration, number of scenes), apply the instruction as far as possible and keep the remaining rules.

        APP
        \(Self.compact(analysis))
        \(post.brief.map { "\nORIGINAL REQUEST\n\($0.prompt)" } ?? "")
        \(post.brief?.findings.map { "\nPREVIOUSLY VERIFIED FACTS\n\($0)\nSources: \((post.brief?.sources ?? []).joined(separator: ", "))" } ?? "")
        \(research ? Self.researchRules : "")

        CURRENT SCRIPT (JSON)
        \(current)

        AVAILABLE SCREENSHOTS (use the file name exactly as given in the image field):
        \(usable.isEmpty ? "(none — do not use screenshot scenes)" : Self.assetList(usable))

        \(rules(targetSeconds: Int(post.spec.totalDuration.rounded()), research: research))
        """
        return try await claude.structured(
            ScriptResult.self,
            prompt: prompt,
            schema: Self.scriptSchema(assetNames: usable.map(\.fileName), maxHashtags: maxHashtags, research: research),
            cwd: project.folderURL,
            tools: research ? Self.researchTools : [],
            maxTurns: research ? 30 : 4,
            onActivity: onActivity
        )
    }

    static let researchTools = ["WebSearch", "WebFetch", "Read", "Glob", "Grep"]

    static var researchRules: String {
        let today = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "en_US")))
        return """

        RESEARCH
        - Today is \(today). Research the current information mentioned in the request (e.g. match date and time, teams, form, injuries, standings, campaign details) with WebSearch and WebFetch.
        - Put on screen and in the voiceover only information you have verified in at least one reliable source. If sources conflict or you cannot verify a piece of information, do not use it; build the script without it and note this in the findings field.
        - Verify relative times ("tomorrow", "tonight") against today's date; in the video use expressions that stay valid regardless of the posting day (e.g. "Saturday 6:30 PM").
        - If an official brand, logo or club name needs to be used, mention it only as text; do not download logos or images.
        - findings: the facts you verified and the ones you could not verify (short bullet points). sources: the links you used.
        """
    }

    static func assetList(_ assets: [ProjectAsset]) -> String {
        assets.map { "- \($0.fileName): \($0.label)\($0.isFramed ? " [framed store image]" : "")" }.joined(separator: "\n")
    }

    /// The script as JSON for Claude (excluding internal fields like the audio file)
    private static func scriptJSON(_ post: ContentPost) -> String {
        let scenes: [[String: Any]] = post.spec.scenes.map { s in
            var d: [String: Any] = ["kind": s.kind.rawValue, "title": s.title, "durationSec": s.durationSec ?? 3]
            if let v = s.subtitle { d["subtitle"] = v }
            if let v = s.image { d["image"] = v }
            if let v = s.imageStyle { d["imageStyle"] = v.rawValue }
            if let v = s.bullets { d["bullets"] = v }
            if let v = s.stat { d["stat"] = v }
            if let v = s.emoji { d["emoji"] = v }
            if let v = s.voiceover { d["voiceover"] = v }
            return d
        }
        let obj: [String: Any] = [
            "title": post.title, "scenes": scenes, "caption": post.caption, "hashtags": post.hashtags,
            "altText": post.altText ?? "", "postingTip": post.postingTip ?? "",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Rules for scene types, text, voiceover and caption (shared by writing and revising)
    private func rules(targetSeconds: Int, research: Bool) -> String {
        """
        SCENE TYPES
        - hook: first scene, 1.5–2.5 s. A single scroll-stopping, curiosity-sparking sentence (at most 6 words) + optional emoji and a short subtitle.
        - screenshot: title (≤6 words) + subtitle + image. imageStyle "phone" for a raw screenshot, "raw" for a framed store image.
        - feature: title + 2-4 short bullet points (bullets, each ≤4 words).
        - stat: only if there is a REAL number found in the analysis/code\(research ? " or verified in your research" : "") (stat field e.g. "78%", "10K+"). Do not use made-up numbers; if there is none, do not use this scene.
        - cta: last scene, 2.5–3 s. A short call to action (like "Try it now") + subtitle.

        RULES
        - 4–7 scenes, total duration about \(targetSeconds) s (via durationSec).
        - In titles, wrap the 1 word to emphasize in *asterisks* (e.g. "Know the match *in advance*").
        - Texts must be in \(language), short, conversational and readable on screen.

        VOICEOVER (voiceover)
        - For each scene, write a single sentence (in \(language)) to be read by an AI voiceover. The scene's duration will be adjusted to the length of this audio.
        - Do not repeat the on-screen text word for word; it should be a natural, friendly spoken sentence that complements it. It should carry the same idea as the on-screen title.
        - Keep it short: 4–8 words for hook and cta, 6–14 words for other scenes. The total voiceover must not exceed about \(targetSeconds) seconds (~2.5 words per second).
        - Every sentence must start with exactly one tone tag: [excited], [curious], [amazed], [friendly] or [serious]. These tags are not read aloud. Never write directions outside the square brackets; the model reads plain text exactly as written.
        - Write symbols the way they are spoken in the video's language (e.g. in English "78 percent" instead of "%78", "dollars" instead of "$").
        \(Self.pronunciationRule(language))
        - caption: optimized for Instagram SEO. The first line is a strong hook containing keywords (the first 125 characters show in the preview). Then 2–4 short lines of value proposition, emoji where appropriate, and a clear CTA at the end (link in profile / comment / save). Do not put hashtags in the caption.
        - hashtags: at most \(maxHashtags), without #; a mix of niche + medium-volume + directly on-topic tags; no irrelevant popular tags.
        - altText: accessibility text describing the video (keywords should appear naturally).
        - postingTip: recommended posting day/time for the target audience and a short rationale.
        """
    }

    // MARK: 3) Caption/hashtag rewrite only

    struct CaptionResult: Decodable {
        var caption: String
        var hashtags: [String]
        var altText: String
    }

    func rewriteCaption(post: ContentPost, analysis: ProjectAnalysis, instruction: String, cwd: URL) async throws -> CaptionResult {
        let scenes = post.spec.scenes.map { "[\($0.kind.rawValue)] \($0.title) \($0.subtitle ?? "") \(($0.bullets ?? []).joined(separator: ", "))" }.joined(separator: "\n")
        let prompt = """
        Rewrite the caption and hashtags for an Instagram Reels video. Language: \(language).

        APP
        \(Self.compact(analysis))

        VIDEO SCENES
        \(scenes)

        CURRENT CAPTION
        \(post.caption)

        \(instruction.isEmpty ? "" : "REQUEST: \(instruction)")

        Rules: The first line is a strong hook containing keywords; short lines; a clear CTA at the end; no hashtags inside the caption. At most \(maxHashtags) hashtags (without #), directly on-topic. altText: accessibility description.
        """
        return try await claude.structured(
            CaptionResult.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": [
                    "caption": ["type": "string"],
                    "hashtags": ["type": "array", "items": ["type": "string"], "maxItems": maxHashtags],
                    "altText": ["type": "string"],
                ],
                "required": ["caption", "hashtags", "altText"],
            ],
            cwd: cwd,
            maxTurns: 4
        )
    }

    // MARK: 4) Adapting to another language

    struct TranslationResult: Decodable {
        struct SceneText: Decodable {
            var title: String
            var subtitle: String?
            var bullets: [String]?
            var stat: String?
            var voiceover: String?
            var image: String?
        }
        var title: String
        var scenes: [SceneText]
        var caption: String
        var hashtags: [String]
        var altText: String
    }

    /// Adapts all of the video's text to the target language (localized for that market, not translated word for word).
    func translate(post: ContentPost, analysis: ProjectAnalysis, project: AppProject, languageCode: String) async throws -> TranslationResult {
        let cwd = project.folderURL
        let usable = Self.assets(for: languageCode, in: project)
        let byName = Dictionary(project.assets.map { ($0.fileName, $0) }, uniquingKeysWith: { a, _ in a })
        let scenes = post.spec.scenes.enumerated().map { i, s in
            var d: [String: Any] = ["index": i, "kind": s.kind.rawValue, "title": s.title]
            if let v = s.subtitle { d["subtitle"] = v }
            if let v = s.bullets { d["bullets"] = v }
            if let v = s.stat { d["stat"] = v }
            if let v = s.voiceover { d["voiceover"] = v }
            if let img = s.image, let a = byName[img] { d["image"] = "\(img) — \(a.label)" }
            return d
        }
        let source = try JSONSerialization.data(withJSONObject: [
            "title": post.title, "scenes": scenes, "caption": post.caption, "hashtags": post.hashtags, "altText": post.altText ?? "",
        ], options: [.prettyPrinted])
        let prompt = """
        Adapt all the texts of the Instagram Reels video below into \(language). Do not translate word for word: use expressions that feel natural to an audience speaking that language and create the same effect.

        APP
        \(Self.compact(analysis))

        SOURCE (JSON)
        \(String(decoding: source, as: UTF8.self))

        IMAGES AVAILABLE IN THE TARGET LANGUAGE (use the file name exactly as given in the image field)
        \(usable.map { "- \($0.fileName): \($0.label)\($0.language == languageCode ? " [in this language]" : " [language unknown, probably the source language]")" }.joined(separator: "\n"))

        Rules:
        - The scenes array must be in the same order and have the same count as the source; leave empty fields empty.
        - image: for every scene that has an image in the source, pick from the list above the image showing the same feature/screen. Prefer the ones marked "[in this language]"; but if there is no local image that truly shows the same content, pick the one with unknown language. For a scene without an image in the source, leave image empty.
        - Keep the *asterisk*-emphasized word in titles (move it to the corresponding word in the target language).
        - On-screen texts must stay short (title ≤6 words, bullet ≤4 words). Do not change app and feature names.
        - voiceover: keep the leading tone tag such as [excited] exactly as is; do not write directions outside the square brackets. Keep the length close to the source.
        - Write units in numbers and the currency in the way appropriate for that market, but do not add any claim that is not in the source.
        - caption: optimized for Instagram SEO; the first line is a hook containing keywords in the target language, with a clear CTA at the end. No hashtags inside the caption.
        - hashtags: at most \(maxHashtags), without #, tags that are actually used in that language (not tags translated from the source language).
        """
        let sceneSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": Self.str, "subtitle": Self.str, "bullets": Self.strArray, "stat": Self.str, "voiceover": Self.str,
                "image": usable.isEmpty ? Self.str : ["type": "string", "enum": usable.map(\.fileName) + [""]] as [String: Any],
            ],
            "required": ["title"],
        ]
        return try await claude.structured(
            TranslationResult.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": [
                    "title": Self.str,
                    "scenes": ["type": "array", "items": sceneSchema, "minItems": scenes.count, "maxItems": scenes.count],
                    "caption": Self.str,
                    "hashtags": ["type": "array", "items": Self.str, "maxItems": maxHashtags],
                    "altText": Self.str,
                ],
                "required": ["title", "scenes", "caption", "hashtags", "altText"],
            ],
            cwd: cwd,
            maxTurns: 4
        )
    }

    // MARK: 5) Simulator capture recipe

    func captureRecipe(project: AppProject, screens: [ProjectAsset], onActivity: @escaping @Sendable (String) -> Void) async throws -> CaptureRecipe {
        let assetDir = Paths.projectAssets(project.id)
        let list = screens.map { "- \($0.fileName) → \(assetDir.appendingPathComponent($0.fileName).path)\n  Label: \($0.label)\($0.originalPath.map { "\n  Path in repository: \($0)" } ?? "")" }.joined(separator: "\n")
        let prompt = """
        Produce a recipe for automatically capturing the screens of the iOS app in this folder in the iOS Simulator in different languages. Promo Studio will perform these steps:
        1. Runs prebuildCommand (if any) inside buildDirectory, then builds and installs with `xcodebuild <projectFile> -scheme <scheme> -destination id=<sim> CODE_SIGNING_ALLOWED=NO build`.
        2. For each screen, an XCUITest launches the app with `<launchArguments> -AppleLanguages (xx) -AppleLocale xx_XX <extraArguments>`, opens the deep link if url is not empty (it handles the system confirmation itself), then taps the elements in the taps list in order, waits waitSeconds and takes a screenshot. It CANNOT scroll or enter text.

        Task:
        - Find in the code the bundleId, buildDirectory (relative to the project root), prebuildCommand (e.g. "xcodegen generate" if XcodeGen is used; empty if not needed), projectFile and scheme of the main iOS app.
        - Find the launch arguments that make the app open with demo/sample data (UI tests, AppEnvironment, ProcessInfo.arguments usages, screenshot tests). Prefer arguments that skip onboarding and load realistic demo data that is localized per language. Do NOT ADD language arguments (-AppleLanguages, -AppleLocale).
        - Open each image below with the Read tool and understand which screen it is. Then, if this screen can be reached with launch arguments, a deep link (URL scheme, onOpenURL, app.open in UI tests) and a few taps if needed, add a shot: id (short kebab-case), label (screen name in \(language)), assetFile (the image's file name, exactly), url (empty if none), extraArguments, taps, waitSeconds (1–3).
        - taps: accessibility identifiers (accessibilityIdentifier) of the elements to tap. Since the screen will be captured in every language, do NOT USE visible text; use only identifiers actually defined in the code or texts that do not change with language (proper names in the sample data such as "Spotify"). Empty array if not needed. Navigation steps in UI tests are a good source.
        - Do NOT ADD a shot for screens that cannot be reached this way (those requiring the camera, text entry or scrolling); mention them briefly in the notes field.
        - Do not make up arguments or links; use only those that actually exist in the code.

        SCREENS TO CAPTURE IN LOCALIZED VERSIONS
        \(list)
        """
        let shot: [String: Any] = [
            "type": "object",
            "properties": [
                "id": Self.str, "label": Self.str,
                "assetFile": ["type": "string", "enum": screens.map(\.fileName)],
                "url": Self.str, "extraArguments": Self.strArray, "taps": Self.strArray, "waitSeconds": ["type": "number"],
            ],
            "required": ["id", "label", "assetFile", "url", "extraArguments", "taps", "waitSeconds"],
        ]
        return try await claude.structured(
            CaptureRecipe.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": [
                    "bundleId": Self.str, "buildDirectory": Self.str, "prebuildCommand": Self.str,
                    "projectFile": Self.str, "scheme": Self.str, "launchArguments": Self.strArray,
                    "shots": ["type": "array", "items": shot], "notes": Self.str,
                ],
                "required": ["bundleId", "buildDirectory", "prebuildCommand", "projectFile", "scheme", "launchArguments", "shots", "notes"],
            ],
            cwd: project.folderURL,
            tools: ["Read", "Glob", "Grep", "Bash(ls:*)", "Bash(find:*)", "Bash(cat:*)", "Bash(head:*)"],
            additionalDirectories: [assetDir],
            maxTurns: 40,
            onActivity: onActivity
        )
    }

    // MARK: 6) Template library skills (e.g. Promo Templates)

    struct SkillRunResult: Decodable {
        var status: String
        var videoPath: String?
        var compositionId: String?
        var propsJson: String?
        var summary: String
        var sources: [String]?
        var notes: String
    }

    /// Runs a library video skill with Claude Code in the background; the skill writes, verifies and renders the video.
    func runSkill(_ skill: String, request: String, library: TemplateLibrary, onActivity: @escaping @Sendable (String) -> Void) async throws -> SkillRunResult {
        let prompt = """
        Run the `\(skill)` skill with the Skill tool. Request to give the skill: \(request.isEmpty ? "(empty — pick one of the skill's ready-made variants)" : request)

        This session was started in the background by Promo Studio (a macOS promo video studio). You cannot ask the user questions or wait for approval.
        - Where things are ambiguous, make the most reasonable choice following the rules of CLAUDE.md and the skill, and write your choice in the notes field.
        - If the skill tells you to ask the user for some information (e.g. real match information could not be verified or sources conflict), do NOT render the video. Return status = "needs_input" and explain in notes what is needed.
        - Do not try to open Studio. Use --port=3100 in render and still commands. Render the MP4 to the location the skill specifies.
        - When finished, return:
          - status: "done"
          - videoPath: absolute path of the MP4
          - compositionId
          - propsJson: the props used in the render, as JSON. If you wrote defaultProps inline, give them exactly; leave empty if there are no props.
          - summary: concept, duration, editable props and known limitations (short)
          - sources: the links you used for verification
          - notes
        - If an error occurs, return status = "failed" and write the reason in notes.
        """
        return try await claude.structured(
            SkillRunResult.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": [
                    "status": ["type": "string", "enum": ["done", "needs_input", "failed"]],
                    "videoPath": Self.str, "compositionId": Self.str, "propsJson": Self.str,
                    "summary": Self.str, "sources": Self.strArray, "notes": Self.str,
                ],
                "required": ["status", "summary", "notes"],
            ],
            cwd: library.rootURL,
            tools: Self.libraryTools,
            maxTurns: 250,
            onActivity: onActivity
        )
    }

    struct IdeasResult: Decodable {
        var ideas: [VideoIdea]
        var sources: [String]
    }

    /// Researches trends with a video-idea style skill and suggests concepts (does not start production).
    func videoIdeas(focus: String, library: TemplateLibrary, onActivity: @escaping @Sendable (String) -> Void) async throws -> IdeasResult {
        let skillNames = library.skills.map(\.name)
        let ideaSkill = skillNames.first { $0.contains("fikir") || $0.contains("idea") }
        let prompt = """
        \(ideaSkill.map { "Run the `\($0)` skill with the Skill tool." } ?? "Research short-form video trends on the web and propose concepts that can be produced with code in this project.") Focus: \(focus.isEmpty ? "general" : focus)

        This session was started in the background by Promo Studio. Proceed only up to the concept proposal step; the choice will be left to the user. Do NOT PRODUCE any video and do not modify files.
        For each concept:
        - skill: the skill that will produce this concept. It must be one of: \(skillNames.filter { $0 != ideaSkill }.joined(separator: ", "))
        - request: a self-contained request text to give that skill (the concept's hook, flow and variant)
        - title, hook, flow, why, difficulty
        sources: the links you used in the trend research.
        """
        let idea: [String: Any] = [
            "type": "object",
            "properties": [
                "title": Self.str, "hook": Self.str, "flow": Self.str, "why": Self.str,
                "skill": ["type": "string", "enum": skillNames.filter { $0 != ideaSkill }],
                "difficulty": Self.str, "request": Self.str,
            ],
            "required": ["title", "hook", "flow", "why", "skill", "difficulty", "request"],
        ]
        return try await claude.structured(
            IdeasResult.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": ["ideas": ["type": "array", "items": idea], "sources": Self.strArray],
                "required": ["ideas", "sources"],
            ],
            cwd: library.rootURL,
            tools: ["Skill", "Read", "Glob", "Grep", "WebSearch", "WebFetch", "Bash(ls:*)"],
            maxTurns: 60,
            onActivity: onActivity
        )
    }

    struct ExternalCaption: Decodable {
        var title: String
        var caption: String
        var hashtags: [String]
        var altText: String
    }

    /// Short title and Instagram caption for a video produced from a library
    func captionForExternal(summary: String, request: String, project: AppProject?, cwd: URL) async throws -> ExternalCaption {
        let context = project?.analysis.map { """
        The video will be posted on the account of the \($0.appName) app. App: \($0.tagline). If the video is not directly related to the app, do not force the app into it; add a natural CTA at the end.
        """ } ?? ""
        let prompt = """
        Write an Instagram caption, hashtags and alt text for the short vertical video (Reels) below. Language: \(language).

        REQUEST: \(request)
        VIDEO SUMMARY: \(summary)
        \(context)

        title: a short internal title shown in the list in Promo Studio (≤ 8 words, the video's topic).
        Rules: The first line must be a curiosity-sparking hook containing keywords (the first 125 characters show in the preview). Use short lines and suitable emojis. At the end, include a call to comment, save or make a prediction that matches the video's own CTA. No hashtags inside the caption. Write at most \(maxHashtags) hashtags (without #, directly on-topic). altText: accessibility text describing the video. Do not add any claim that is not in the video.
        """
        return try await claude.structured(
            ExternalCaption.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": [
                    "title": Self.str,
                    "caption": Self.str,
                    "hashtags": ["type": "array", "items": Self.str, "maxItems": maxHashtags],
                    "altText": Self.str,
                ],
                "required": ["title", "caption", "hashtags", "altText"],
            ],
            cwd: cwd,
            maxTurns: 4
        )
    }

    /// Tools library skills need: writing files, npx/npm/node commands and web verification
    static let libraryTools = [
        "Skill", "Read", "Write", "Edit", "MultiEdit", "Glob", "Grep", "WebSearch", "WebFetch", "TodoWrite",
        "Bash(npx:*)", "Bash(npm:*)", "Bash(node:*)", "Bash(cd:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(head:*)",
        "Bash(tail:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(wc:*)", "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)",
        "Bash(ffprobe:*)", "Bash(ffmpeg:*)", "Bash(sips:*)", "Bash(git status:*)", "Bash(git diff:*)",
    ]

    // MARK: Helpers

    /// Images usable for a video in a language: those in that language + those of unknown language.
    /// All of them if there are none in that language.
    static func assets(for languageCode: String, in project: AppProject) -> [ProjectAsset] {
        // Unknown-language images that have a localized version are replaced by it
        let replaced = Set(project.assets.filter { $0.language == languageCode }.compactMap(\.variantOf))
        let local = project.assets.filter { $0.language == languageCode || ($0.language == nil && !replaced.contains($0.fileName)) }
        return local.isEmpty ? project.assets : local
    }

    static func compact(_ a: ProjectAnalysis) -> String {
        """
        Name: \(a.appName) — \(a.tagline)
        Summary: \(a.summary)
        Category: \(a.category) · Target audience: \(a.targetAudience) · Tone: \(a.tone)
        Features:\(a.features.map { "\($0.name) (\($0.summary))" }.joined(separator: "; "))
        """
    }

    static let str: [String: Any] = ["type": "string"]
    static let strArray: [String: Any] = ["type": "array", "items": str]

    static let analysisSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "appName": str, "tagline": str, "summary": str, "category": str, "targetAudience": str,
            "platforms": strArray, "tone": str,
            "brandColors": [
                "type": "object",
                "properties": ["primary": str, "accent": str, "background": str],
                "required": ["primary", "accent", "background"],
            ],
            "features": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["id": str, "name": str, "emoji": str, "summary": str, "whyItMatters": str, "hooks": strArray],
                    "required": ["id", "name", "emoji", "summary", "whyItMatters", "hooks"],
                ],
            ],
            "suggestions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": str, "title": str, "featureId": str, "angle": str, "hook": str,
                        "theme": ["type": "string", "enum": VideoTheme.allCases.map(\.rawValue)],
                    ],
                    "required": ["id", "title", "featureId", "theme", "angle", "hook"],
                ],
            ],
            "screenshots": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["path": str, "label": str, "isFramed": ["type": "boolean"]],
                    "required": ["path", "label", "isFramed"],
                ],
            ],
            "logoPath": str,
            "storeURL": str,
        ],
        "required": ["appName", "tagline", "summary", "category", "targetAudience", "platforms", "tone", "brandColors", "features", "suggestions", "screenshots"],
    ]

    static func scriptSchema(assetNames: [String], maxHashtags: Int, research: Bool = false) -> [String: Any] {
        var image: [String: Any] = ["type": "string"]
        if !assetNames.isEmpty { image["enum"] = assetNames }
        return [
            "type": "object",
            "properties": [
                "title": str,
                "scenes": [
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 8,
                    "items": [
                        "type": "object",
                        "properties": [
                            "kind": ["type": "string", "enum": VideoSpec.SceneKind.allCases.map(\.rawValue)],
                            "title": str,
                            "subtitle": str,
                            "image": image,
                            "imageStyle": ["type": "string", "enum": ["phone", "raw"]],
                            "bullets": strArray,
                            "stat": str,
                            "emoji": str,
                            "durationSec": ["type": "number"],
                            "voiceover": str,
                        ],
                        "required": ["kind", "title", "durationSec", "voiceover"],
                    ],
                ],
                "caption": str,
                "hashtags": ["type": "array", "items": str, "maxItems": maxHashtags],
                "altText": str,
                "postingTip": str,
                "findings": str,
                "sources": strArray,
            ],
            "required": ["title", "scenes", "caption", "hashtags", "altText", "postingTip"] + (research ? ["findings", "sources"] : []),
        ]
    }
}
