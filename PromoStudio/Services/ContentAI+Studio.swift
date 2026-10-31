import Foundation

/// Claude-directed promo videos: writing/revising the storyboard and writing the Remotion code.
extension ContentAI {
    struct StoryboardResult: Decodable {
        var title: String
        var concept: String
        var scenes: [StoryScene]
        var caption: String
        var hashtags: [String]
        var altText: String
        var postingTip: String
        var findings: String?
        var sources: [String]?

        var storyboard: Storyboard { Storyboard(concept: concept, scenes: scenes) }
    }

    struct ProductionResult: Decodable {
        var summary: String
        var notes: String
    }

    /// Brand kit info of the linked library (e.g. Acme project ↔ src/Acme in the template library)
    struct BrandKit {
        var libraryRoot: URL
        var sourceFolder: URL
        /// Public path of the images copied into the studio (for staticFile)
        var publicPath: String?
    }

    func writeStoryboard(
        project: AppProject,
        languageCode: String,
        analysis: ProjectAnalysis,
        feature: AppFeature?,
        brief: PostBrief,
        targetSeconds: Int,
        voiceover: Bool,
        brandKit: BrandKit?,
        onActivity: @escaping @Sendable (String) -> Void
    ) async throws -> StoryboardResult {
        let usable = Self.assets(for: languageCode, in: project)
        let prompt = """
        You are an award-winning commercial director and motion graphics designer. Design a \(targetSeconds)-second vertical (1080×1920) promo film for the Instagram/TikTok account of the app below. The film will be custom-built scene by scene in code with Remotion. At this stage you are only writing the STORYBOARD; once the user approves it, a developer will turn it into code one-to-one.

        USER'S REQUEST
        \(brief.prompt)

        APP
        \(Self.compact(analysis))
        \(feature.map { "Feature to spotlight: \($0.emoji) \($0.name) — \($0.summary)" } ?? "")
        \(brief.research ? Self.researchRules : "")

        DIRECTING PRINCIPLES
        - This is NOT a screenshot slideshow. Build a commercial with a story and rhythm: kinetic typography, number and probability animations, notification cards, countdowns, a matchup scoreboard, pitch/arena atmosphere, particle and flash effects, camera shake, hard cuts.
        - Use screenshots only to prove the product, in at most 1–2 scenes; if possible in a cinematic way such as a zoom-in (ZoomShot) or a 3D tilted phone.
        - The first 1.5 seconds must be a scroll-stopping hook. Last scene is the CTA: app name/icon and store badge.
        - Define the visual language in the concept: color palette (brand colors), typography (display/condensed/heading), rhythm (fast cuts or smooth transitions), atmosphere.
        - In each scene's visual field, write with enough clarity for the developer to understand: what is visible, where, how it enters/exits, which kit components (from the list below), timing accents ("flash at 0.5 s", "number counts from 0 to 78").
        - Real-world information (date, time, team, numbers) is used only if verified or present in the app information. Official club/league/brand logos are not used; colors and an abbreviation badge (Badge) are used instead.

        KIT (the building blocks available to the developer)
        Kinetic (title with rise/pop/slam word animation), Typewriter, Caption, Phone (phone frame, tilt, float), ZoomShot (zoom into a region of the screen), AppIcon, Counter (counting number), ProbabilityBar (three-way probability bar), BarChart, Countdown, Badge (color badge), Matchup (matchup scoreboard), Notification (notification card), Chip (LIVE/NEW/PRO label), GlassCard, Ticker (scrolling band), StaggerList, GradientBg, Spotlight, GridFloor, Pitch (football pitch), Particles, Burst (confetti), Flash, Vignette, useShake/usePunch/useDrift; sound effects: whoosh, whip, switch, ding, click, pageTurn, shutter, notification, boom, dramatic, recordScratch, yippee, wow. If needed, the developer can also do custom drawing (SVG, CSS shapes).
        \(brandKit.map { "\nBRAND KIT\nThis project has a ready-made brand kit: \($0.sourceFolder.path) (you may read it; especially the brand rules in CLAUDE.md, if present: \($0.libraryRoot.appendingPathComponent("CLAUDE.md").path)). You may refer to kit elements such as stickers, icons and intro animations by name in the storyboard." } ?? "")

        PROJECT IMAGES (use the file name exactly as given in the assets field)
        \(usable.isEmpty ? "(none)" : Self.assetList(usable))

        SCENES
        - 5–9 scenes, total duration about \(targetSeconds) s (via durationSec; hook 1.2–2 s).
        - text: the main on-screen text, short (≤7 words), in \(language). Wrap the word to emphasize in *asterisks*.
        \(voiceover ? """
        - voiceover: For each scene, a single sentence (in \(language)) to be read by an AI voiceover. Do not repeat the on-screen text; it should complement it. Hook and CTA 4–8 words, others 6–14 words. The total must not exceed ~\(targetSeconds) s (~2.5 words per second). Every sentence must start with exactly one tone tag: [excited], [curious], [amazed], [friendly] or [serious]. Write symbols the way they are spoken in the video's language (e.g. in English "78 percent" instead of "%78"). The scene duration will be adjusted to the length of the audio.
        """ : "- Leave the voiceover field empty (this video has no voiceover).")
        - sfx: the scene's sound effect(s) and their moment (e.g. "boom 0.2 s"), empty if none.
        - assets: project images to use in the scene (empty array if none).

        CAPTION
        - caption: optimized for Instagram SEO; the first line is a strong keyword hook (first 125 characters), 2–4 short lines, suitable emoji, a clear CTA at the end. Do not put hashtags in the caption.
        - hashtags: at most \(maxHashtags), without #, directly on-topic.
        - altText: accessibility text describing the video. postingTip: recommended posting time and rationale.
        """
        return try await claude.structured(
            StoryboardResult.self,
            prompt: prompt,
            schema: Self.storyboardSchema(assetNames: usable.map(\.fileName), maxHashtags: maxHashtags, research: brief.research),
            cwd: project.folderURL,
            tools: brief.research ? Self.researchTools : ["Read", "Glob", "Grep"],
            maxTurns: brief.research ? 40 : 12,
            onActivity: onActivity
        )
    }

    /// Updates the storyboard per the instruction (scenes not mentioned are kept).
    func reviseStoryboard(post: ContentPost, project: AppProject, analysis: ProjectAnalysis, instruction: String, produced: Bool, onActivity: @escaping @Sendable (String) -> Void) async throws -> StoryboardResult {
        let usable = Self.assets(for: post.language ?? "tr", in: project)
        let research = post.brief?.research ?? false
        let board = post.directed?.storyboard ?? Storyboard(concept: "", scenes: [])
        let current = Self.storyboardJSON(post: post, board: board)
        let prompt = """
        You are an award-winning commercial director. Update the promo film storyboard below according to the user's REVISION INSTRUCTION.

        REVISION INSTRUCTION
        \(instruction)

        - Change only what the instruction requires; keep the scenes, texts, voiceovers, caption and hashtags the instruction does not touch exactly as they are.
        \(produced ? "- The video has already been coded. If the instruction concerns only visuals/motion/timing (color, animation, effects, layout), update the visual fields; do not change text and voiceover (so the voiceover is not regenerated)." : "")
        - If the instruction requires new information, \(research ? "research and verify it" : "rely on the app information; do not make anything up").
        - If there is a voiceover, every sentence must start with a tone tag ([excited], [curious], [amazed], [friendly], [serious]).

        APP
        \(Self.compact(analysis))
        \(post.brief.map { "\nORIGINAL REQUEST\n\($0.prompt)" } ?? "")
        \(post.brief?.findings.map { "\nPREVIOUSLY VERIFIED FACTS\n\($0)" } ?? "")
        \(research ? Self.researchRules : "")

        CURRENT STORYBOARD (JSON)
        \(current)

        PROJECT IMAGES
        \(usable.isEmpty ? "(none)" : Self.assetList(usable))
        """
        return try await claude.structured(
            StoryboardResult.self,
            prompt: prompt,
            schema: Self.storyboardSchema(assetNames: usable.map(\.fileName), maxHashtags: maxHashtags, research: research),
            cwd: project.folderURL,
            tools: research ? Self.researchTools : [],
            maxTurns: research ? 30 : 4,
            onActivity: onActivity
        )
    }

    /// Turns the storyboard into Remotion code (or edits the existing code per the instruction) and verifies it visually with stills.
    func produceVideo(post: ContentPost, analysis: ProjectAnalysis, brandKit: BrandKit?, revision: String?, onActivity: @escaping @Sendable (String) -> Void) async throws -> ProductionResult {
        guard let directed = post.directed else { throw StudioError.noStoryboard }
        let id = directed.compositionId
        let folder = "src/videos/\(id)"
        let props = "public/posts/\(post.id.uuidString)/props.json"
        let previews = "public/posts/\(post.id.uuidString)/preview"
        let task = revision.map { """
            TASK: Edit the existing video in the \(folder)/ folder according to the user's REVISION INSTRUCTION. The storyboard and props have been updated according to this instruction (scene durations and audio may have changed). Keep the scenes the instruction does not touch.

            REVISION INSTRUCTION
            \($0)
            """ } ?? """
            TASK: Turn the approved storyboard below into code in \(folder)/Video.tsx as `export const Video: React.FC<StudioProps>`. Stay faithful to the storyboard; implement every motion and effect in the director's notes.
            """
        let prompt = """
        You are a senior motion graphics developer (Remotion 4, React). You are coding an app's vertical promo film. The working folder is Promo Studio's Remotion studio.

        \(task)

        PREPARATION
        1. Read KIT.md and src/kit/example/ExampleVideo.tsx; look at the files in src/kit/ for kit component signatures if needed. Load the Remotion skills (remotion-best-practices) if available.
        2. Read the props: \(props) — scene timings (from, durationInFrames), audio files, image paths and brand colors come from here. Do not change scene timings; use the Timeline component.
        \(brandKit.map { kit in "3. BRAND KIT: \(kit.sourceFolder.path) (read-only) and the brand rules in \(kit.libraryRoot.appendingPathComponent("CLAUDE.md").path). Do NOT IMPORT these files (it is a different Remotion project); write the components you need by adapting them inside \(folder)/. \(kit.publicPath.map { "The kit's images have been copied into the studio: use them with staticFile('\($0)/...') (see the public/\($0) folder for file names)." } ?? "")" } ?? "")

        RULES
        - Write only inside the \(folder)/ folder (you may create sub-files for helper components). Do not touch kit files or other folders. Import kit components from the '../../kit' path.
        - The rules in KIT.md apply: safe area, readable sizes, frame-based animation only, no Math.random, uppercase text written in uppercase in the source (no textTransform, which breaks Turkish i/İ), no official logos.
        - Quality bar: it must look like it came from an agency. Layered backgrounds, depth (shadow, glow, blur), moving camera (drift, shake, punch), clear hierarchy. Do not leave empty or static frames.
        - The entry file is ready: src/entries/\(id).tsx (composition id: \(id)).

        VERIFICATION (mandatory)
        1. Run `npx tsc --noEmit`; fix all errors in \(folder)/ (ignore errors in other folders).
        2. Take a frame from the middle of each scene and from the first second of the hook:
           `npx remotion still src/entries/\(id).tsx \(id) \(previews)/sN.png --props=\(props) --frame=<frame> --scale=0.4 --log=error`
           Open the frames with Read and inspect them: text overflow, unreadable text, overlapping elements, empty frames, deviations from the storyboard. Fix the problems and check again.
        3. When finished, return summary (a short description of the video) and notes (known limitations, deviations from the storyboard). Promo Studio will do the final render; do not render it yourself.

        STORYBOARD (JSON)
        \(Self.storyboardJSON(post: post, board: directed.storyboard))

        APP
        \(Self.compact(analysis))
        """
        return try await claude.structured(
            ProductionResult.self,
            prompt: prompt,
            schema: [
                "type": "object",
                "properties": ["summary": Self.str, "notes": Self.str],
                "required": ["summary", "notes"],
            ],
            cwd: Paths.remotion,
            tools: ["Read", "Glob", "Grep", "Skill", "Edit(\(folder)/**)", "Bash(npx tsc:*)", "Bash(npx remotion still:*)", "Bash(ls:*)"],
            maxTurns: 150,
            onActivity: onActivity
        )
    }

    static func storyboardJSON(post: ContentPost, board: Storyboard) -> String {
        let scenes: [[String: Any]] = board.scenes.map { s in
            var d: [String: Any] = ["visual": s.visual, "text": s.text, "durationSec": s.durationSec, "assets": s.assets ?? []]
            if let v = s.voiceover { d["voiceover"] = v }
            if let v = s.sfx { d["sfx"] = v }
            return d
        }
        let obj: [String: Any] = [
            "title": post.title, "concept": board.concept, "scenes": scenes, "caption": post.caption,
            "hashtags": post.hashtags, "altText": post.altText ?? "", "postingTip": post.postingTip ?? "",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func storyboardSchema(assetNames: [String], maxHashtags: Int, research: Bool) -> [String: Any] {
        var asset: [String: Any] = ["type": "string"]
        if !assetNames.isEmpty { asset["enum"] = assetNames }
        return [
            "type": "object",
            "properties": [
                "title": str,
                "concept": str,
                "scenes": [
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 10,
                    "items": [
                        "type": "object",
                        "properties": [
                            "visual": str, "text": str, "voiceover": str, "sfx": str,
                            "assets": ["type": "array", "items": asset],
                            "durationSec": ["type": "number"],
                        ],
                        "required": ["visual", "text", "durationSec"],
                    ],
                ],
                "caption": str,
                "hashtags": ["type": "array", "items": str, "maxItems": maxHashtags],
                "altText": str,
                "postingTip": str,
                "findings": str,
                "sources": strArray,
            ],
            "required": ["title", "concept", "scenes", "caption", "hashtags", "altText", "postingTip"] + (research ? ["findings", "sources"] : []),
        ]
    }
}
