import Foundation

/// Claude-directed videos (promo films and free-form videos): writing/revising the storyboard and writing the Remotion code.
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
        var logos: [StoryLogo]?
        var people: [StoryPerson]?
        var coverScene: Int?

        var storyboard: Storyboard { Storyboard(concept: concept, scenes: scenes, logos: logos, people: people, coverScene: coverScene) }
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
        style: DirectedStyle,
        brandKit: BrandKit?,
        uploads: [URL] = [],
        image: ImageSize? = nil,
        slides: Int = 1,
        onActivity: @escaping @Sendable (String) -> Void
    ) async throws -> StoryboardResult {
        let usable = Self.assets(for: languageCode, in: project)
        let freeform = style == .freeform
        let opening: String
        if let image {
            let px = image.pixels
            opening = slides > 1
                ? "You are an award-winning art director and graphic designer. Design a \(slides)-slide CAROUSEL post for Instagram, each slide \(px.width)×\(px.height), exactly as the user describes it below\(freeform ? ". It is posted from the account of the app below, but it is NOT an ad for the app" : ", promoting the app below"). People swipe through the slides: the first stops the scroll, the middle ones deliver the content one idea per slide, the last one closes it (a takeaway or a CTA). One visual system across all slides. The slides will be built in code with Remotion and rendered as stills. At this stage you are only writing the DESIGN BRIEF as a storyboard with one scene per slide; once the user approves it, a developer will build it one-to-one."
                : "You are an award-winning art director and graphic designer. Design a single \(px.width)×\(px.height) IMAGE post for Instagram exactly as the user describes it below\(freeform ? ". It is posted from the account of the app below, but it is NOT an ad for the app" : ", promoting the app below"). The image will be built in code with Remotion and rendered as a still. At this stage you are only writing the DESIGN BRIEF as a one-scene storyboard; once the user approves it, a developer will build it one-to-one."
        } else if freeform {
            opening = "You are an award-winning director and motion graphics designer. Design a \(targetSeconds)-second vertical (1080×1920) video for Instagram/TikTok exactly as the user describes it below. It is posted from the account of the app below, but it is NOT an ad for the app. The video will be custom-built scene by scene in code with Remotion. At this stage you are only writing the STORYBOARD; once the user approves it, a developer will turn it into code one-to-one."
        } else {
            opening = "You are an award-winning commercial director and motion graphics designer. Design a \(targetSeconds)-second vertical (1080×1920) promo film for the Instagram/TikTok account of the app below. The film will be custom-built scene by scene in code with Remotion. At this stage you are only writing the STORYBOARD; once the user approves it, a developer will turn it into code one-to-one."
        }
        let uploadNames = uploads.map(\.lastPathComponent)
        let prompt = """
        \(opening)

        USER'S REQUEST
        \(brief.prompt)

        \(freeform ? "ACCOUNT (background only: brand colors and name; do not advertise it)" : "APP")
        \(Self.compact(analysis))
        \(feature.map { "Feature to spotlight: \($0.emoji) \($0.name) — \($0.summary)" } ?? "")
        \(brief.research ? Self.researchRules : "")

        DIRECTING PRINCIPLES
        \(freeform ? Self.freeformRules : Self.promoRules)
        - Define the visual language in the concept: color palette (brand colors), typography (display/condensed/heading), rhythm (fast cuts or smooth transitions), atmosphere.
        - In each scene's visual field, write with enough clarity for the developer to understand: what is visible, where, how it enters/exits, which kit components (from the list below), timing accents ("flash at 0.5 s", "number counts from 0 to 78").
        - Real-world information (date, time, team, numbers) is used only if verified or present in the app information.
        \(Self.logoRule)
        \(peopleRule)
        \(uploads.isEmpty ? "" : Self.uploadsRule(uploads))

        KIT (the building blocks available to the developer)
        Portrait (a real person's cut-out photo with a mood: fierce, heroic, mono, natural, and a team-color rim light), FaceOff (two people face to face with VS), Kinetic (title with rise/pop/slam word animation), Typewriter, Caption, Phone (phone frame, tilt, float), ZoomShot (zoom into a region of the screen), AppIcon, Counter (counting number), ProbabilityBar (three-way probability bar), BarChart, Countdown, Badge (color badge), Matchup (matchup scoreboard), Notification (notification card), Chip (LIVE/NEW/PRO label), GlassCard, Ticker (scrolling band), StaggerList, GradientBg, Spotlight, GridFloor, Pitch (football pitch), Particles, Burst (confetti), Flash, Vignette, useShake/usePunch/useDrift; sound effects: whoosh, whip, switch, ding, click, pageTurn, shutter, notification, boom, dramatic, recordScratch, yippee, wow. If needed, the developer can also do custom drawing (SVG, CSS shapes).
        \(brandKit.map { "\nBRAND KIT\nThis project has a ready-made brand kit: \($0.sourceFolder.path) (you may read it; especially the brand rules in CLAUDE.md, if present: \($0.libraryRoot.appendingPathComponent("CLAUDE.md").path)). You may refer to kit elements such as stickers, icons and intro animations by name in the storyboard." } ?? "")

        PROJECT IMAGES (use the file name exactly as given in the assets field)
        \(usable.isEmpty ? "(none)" : Self.assetList(usable))

        \(image != nil && slides > 1 ? """
        THE SLIDES (exactly \(slides) scenes, one per slide, in order)
        - visual: the complete layout of that slide: what is where (top to bottom), sizes, colors, typography, photos and how they are treated. Repeat the shared elements (background, type, a slide counter or swipe cue if used) so each slide can be built on its own.
        - text: the slide's headline, short (≤7 words), in \(language). Wrap the word to emphasize in *asterisks*. Other texts on the slide go in visual.
        - durationSec: 2 for every slide. Leave voiceover and sfx empty. coverScene: 0.
        """ : image != nil ? """
        THE IMAGE (exactly one scene)
        - visual: the complete layout: what is where (top to bottom), sizes, colors, typography, photos and how they are treated, depth and light. Everything must read in a second on a phone.
        - text: the headline, short (≤7 words), in \(language). Wrap the word to emphasize in *asterisks*. Other texts on the image go in visual.
        - durationSec: 2. Leave voiceover and sfx empty. coverScene: 0.
        """ : """
        SCENES
        - 5–9 scenes, total duration about \(targetSeconds) s (via durationSec; hook 1.2–2 s).
        - text: the main on-screen text, short (≤7 words), in \(language). Wrap the word to emphasize in *asterisks*.
        \(voiceover ? """
        - voiceover: For each scene, a single sentence (in \(language)) to be read by an AI voiceover. Do not repeat the on-screen text; it should complement it. Hook and CTA 4–8 words, others 6–14 words. The total must not exceed ~\(targetSeconds) s (~2.5 words per second). Every sentence must start with exactly one tone tag: [excited], [curious], [amazed], [friendly] or [serious]. Write symbols the way they are spoken in the video's language (e.g. in English "78 percent" instead of "%78"). The scene duration will be adjusted to the length of the audio.
        \(Self.pronunciationRule(language))
        """ : "- Leave the voiceover field empty (this video has no voiceover).")
        - sfx: the scene's sound effect(s) and their moment (e.g. "boom 0.2 s"), empty if none.
        - assets: project images to use in the scene (empty array if none\(freeform ? "; leave empty unless the request calls for the app" : "")).
        - coverScene: index (0-based) of the scene whose fully settled frame makes the most eye-catching cover (big readable title or the key visual on screen, not a transition). This frame becomes the Instagram cover.
        """)

        CAPTION
        - caption: optimized for Instagram SEO; the first line is a strong keyword hook (first 125 characters), 2–4 short lines, suitable emoji, \(freeform ? "a CTA at the end only if it fits the request" : "a clear CTA at the end"). Do not put hashtags in the caption.
        - hashtags: at most \(maxHashtags), without #, directly on-topic.
        - altText: accessibility text describing the video. postingTip: recommended posting time and rationale.
        """
        return try await claude.structured(
            StoryboardResult.self,
            prompt: prompt,
            schema: Self.storyboardSchema(assetNames: usable.map(\.fileName) + uploadNames, maxHashtags: maxHashtags, research: brief.research, image: image != nil, slides: slides),
            cwd: project.folderURL,
            tools: brief.research ? Self.researchTools : ["Read", "Glob", "Grep", "WebFetch"],
            additionalDirectories: uploads.isEmpty ? [] : [uploads[0].deletingLastPathComponent()],
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
        let freeform = post.directed?.isFreeform == true
        let uploads = StudioService.uploadFiles(post).map { Paths.post(post.id).appendingPathComponent($0.1) }
        let slides = post.isImage ? max(1, board.scenes.count) : 1
        let prompt = """
        You are an award-winning \(post.isImage ? "art director" : freeform ? "director" : "commercial director"). Update the \(slides > 1 ? "carousel design (one scene per slide; keep exactly \(slides) scenes)" : post.isImage ? "image post design (a one-scene storyboard; keep it one scene)" : freeform ? "video" : "promo film") storyboard below according to the user's REVISION INSTRUCTION.

        REVISION INSTRUCTION
        \(instruction)

        - Change only what the instruction requires; keep the scenes, texts, voiceovers, caption and hashtags the instruction does not touch exactly as they are.
        \(produced ? "- The video has already been coded. If the instruction concerns only visuals/motion/timing (color, animation, effects, layout), update the visual fields; do not change text and voiceover (so the voiceover is not regenerated)." : "")
        - If the instruction requires new information, \(research ? "research and verify it" : "rely on the app information; do not make anything up").
        - If there is a voiceover, every sentence must start with a tone tag ([excited], [curious], [amazed], [friendly], [serious]).
        \(Self.pronunciationRule(language))
        \(Self.logoRule)
        \(peopleRule)
        \(uploads.isEmpty ? "" : Self.uploadsRule(uploads))
        - Keep the logos and people lists and coverScene unless the instruction changes them; update coverScene if the scenes change.
        \(freeform ? "- This is a free-form video, not an app ad: do not add app features, screenshots or a store CTA unless the instruction or the original request asks for them." : "")

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
            schema: Self.storyboardSchema(assetNames: usable.map(\.fileName) + (post.uploads ?? []), maxHashtags: maxHashtags, research: research, image: post.isImage, slides: slides),
            cwd: project.folderURL,
            tools: research ? Self.researchTools : ["Read", "Glob", "Grep", "WebFetch"],
            additionalDirectories: uploads.isEmpty ? [] : [uploads[0].deletingLastPathComponent()],
            maxTurns: research ? 30 : 8,
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
        let px = (directed.size ?? .portrait).pixels
        let slides = directed.storyboard.scenes.count
        let imageRules = post.isImage && slides > 1 ? """
            - THIS IS A CAROUSEL OF \(slides) STILL SLIDES, each \(px.width)×\(px.height) (props.width × props.height; read them with useVideoConfig, don't assume 1080×1920). Each storyboard scene is one slide: use the Timeline component so scene i plays from props.scenes[i].from for 60 frames. Promo Studio renders the last frame of each scene (frames 59, 119, 179…) as that slide: everything in a slide must be fully in place by its 45th frame (entrance animations are fine, but nothing may still be moving or fading at its last frame). No audio or sound effects. Keep one visual system across the slides. Adapt the safe area to the size (60 px from every edge).
            """ : post.isImage ? """
            - THIS IS A STILL IMAGE, \(px.width)×\(px.height) (props.width × props.height; read them with useVideoConfig, don't assume 1080×1920). The storyboard has one scene that describes the whole image. Promo Studio renders frame 59, the last frame, as the picture: everything must be fully in place by frame 45 (entrance animations are fine, but nothing may still be moving or fading at frame 59). No Timeline, audio or sound effects. Adapt the safe area to the size (60 px from every edge).
            """ : ""
        let prompt = """
        You are a senior motion graphics developer (Remotion 4, React). \(directed.isFreeform ? "You are coding a vertical video for an app's social account. It is not an app ad: build exactly what the storyboard describes and do not add app screenshots, store badges or CTA cards it doesn't have." : "You are coding an app's vertical promo film.") The working folder is Promo Studio's Remotion studio.

        \(task)

        PREPARATION
        1. Read KIT.md and src/kit/example/ExampleVideo.tsx; look at the files in src/kit/ for kit component signatures if needed. Load the Remotion skills (remotion-best-practices) if available.
        2. Read the props: \(props) — scene timings (from, durationInFrames), audio files, image paths and brand colors come from here. Do not change scene timings; use the Timeline component.
        \(brandKit.map { kit in "3. BRAND KIT: \(kit.sourceFolder.path) (read-only) and the brand rules in \(kit.libraryRoot.appendingPathComponent("CLAUDE.md").path). Do NOT IMPORT these files (it is a different Remotion project); write the components you need by adapting them inside \(folder)/. \(kit.publicPath.map { "The kit's images have been copied into the studio: use them with staticFile('\($0)/...') (see the public/\($0) folder for file names)." } ?? "")" } ?? "")

        RULES
        - Write only inside the \(folder)/ folder (you may create sub-files for helper components). Do not touch kit files or other folders. Import kit components from the '../../kit' path.
        - The rules in KIT.md apply: safe area, readable sizes, frame-based animation only, no Math.random, uppercase text written in uppercase in the source (no textTransform, which breaks Turkish i/İ).
        \(imageRules)
        - Real people: props.people maps each name in the storyboard's people list to {photo, cutout?} (cutout: the same photo with the background removed). Show them with the kit Portrait or FaceOff, or an <Img> of the cutout/photo, wherever the storyboard shows that person. Never draw a real person as a silhouette, stick figure, emoji or avatar. A name missing from props.people has no photo: show them with typography instead (name, shirt number, team colors). In the verification stills, check that each photo shows that person, is not cut off awkwardly, and faces the way the scene needs (use flip); the mood comes from the treatment, color, light and motion, since the photo itself can't be changed.
        - Uploaded images: props.uploads maps the user's image file names to {photo, cutout?}, and scene.assets include them as public paths. Use them as the storyboard says (full-bleed with a slow push, the cutout over a new background, a framed card…).
        - Real logos: props.logos maps each name in the storyboard's logos list to its downloaded image (public path). Show them with the kit Logo, Matchup's logo field, or <Img src={staticFile(path)}> with objectFit 'contain', wherever the storyboard shows that club/league/brand, even where a visual field still mentions a Badge for it; never redraw a real logo in SVG/CSS. A name missing from props.logos has no image: use colors and an abbreviation Badge for it. In the verification stills, check that every logo shows the right club/brand; if one is clearly wrong, use a Badge instead and say so in notes.
        - Quality bar: it must look like it came from an agency. Layered backgrounds, depth (shadow, glow, blur), moving camera (drift, shake, punch), clear hierarchy. Do not leave empty or static frames.
        - The entry file is ready: src/entries/\(id).tsx (composition id: \(id)).

        VERIFICATION (mandatory)
        1. Run `npx tsc --noEmit`; fix all errors in \(folder)/ (ignore errors in other folders).
        2. \(post.isImage && slides > 1 ? "Take the last frame of each slide (59, 119, 179…) at --scale=0.5 and check each like a designer: hierarchy, contrast, readable at phone size, nothing cut off, and the slides look like one set." : post.isImage ? "Take frame 59 at --scale=0.5 (that is the picture) and check it like a designer: hierarchy, contrast, readable at phone size, nothing cut off." : "Take a frame from the middle of each scene and from the first second of the hook:")
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

    /// Real logos: listed with a source URL in the storyboard, downloaded by Promo Studio, shown as images in the code.
    static let logoRule = """
    - Real logos: when the video shows real clubs, leagues, competitions or brands, show their real logos instead of drawn ones. List EVERY one of them in the logos field, the opponent as much as the home side, and plan their logos in the visual fields, not badges or drawn crests. Each entry: name (as written in the visual fields), plus at least one of:
      - wiki: the exact English Wikipedia article title of that club/league/brand (e.g. "VfB Stuttgart", "Galatasaray S.K. (football)", "UEFA Champions League"). Promo Studio downloads the article's lead image, which is the crest or logo. Give it for every entry; use WebFetch on en.wikipedia.org to confirm the title if unsure.
      - url: a direct link to the official logo image (PNG, SVG or WebP), only if you have confirmed it, e.g. the source the app itself uses (a football app may load crests from media.api-sports.io/football/teams/<id>.png: take the id from the app's code or data, never guess it). It's tried first; wiki is the fallback.
      Only a logo that can't be downloaded falls back to colors and an abbreviation badge (Badge).
    """

    /// Real people: listed with a photo source in the storyboard, downloaded and cut out by Promo Studio, shown with Portrait/FaceOff.
    var peopleRule: String {
        Self.peopleBaseRule + (editPhotos ? Self.photoEditRule : "")
    }

    static let peopleBaseRule = """
    - Real people: when the video shows real, well-known people (players, coaches, athletes, artists, public figures), show their real photos, never silhouettes, stick figures or drawn avatars. List EVERY one of them in the people field: name (as written in the visual fields), plus wiki (the exact English Wikipedia article title, e.g. "Deniz Undav", "Ermedin Demirović"; use WebFetch on en.wikipedia.org to confirm it if unsure) and/or url (a direct link to a photo of them that you confirmed). Promo Studio downloads the photo and cuts the person out of the background. Many articles have no photo: if the article shows none, look for a direct photo link (the club's or league's player page, a press image) and give it as url; a clear, front-facing photo of just that person works best. If the user uploaded a photo of the person, use that upload instead.
      In the visual fields, plan how they appear with the kit: Portrait (one person; mood fierce, heroic, mono or natural; a rim light in the team color) or FaceOff (two people face to face with a VS). Without an edit, a photo keeps its pose and facial expression: create the feeling (e.g. ambitious, fierce, face to face) with the mood, color, light, contrast, framing and motion.
    """

    /// Codex edits the downloaded photos when the storyboard asks for it
    static let photoEditRule = """

      PHOTO EDITS: Promo Studio can have an image model (Codex image generation) edit each downloaded photo before it is cut out. When the request asks for a look the photo is unlikely to have (an ambitious or fierce expression, looking at the camera, a celebration, a pose, dramatic stadium light) or two people have to face each other, give the person an edit: one instruction in English for the image model, e.g. "fierce, determined expression, looking straight into the camera, clenched fist, dramatic red stadium backlight". The person's face, identity and kit are kept as they are; ask only for expression, gaze, pose, light and framing (not other people, logos, text or a different kit). For two people facing each other, have one look toward the right of the frame and the other toward the left. Leave edit empty when the downloaded photo works as it is.
    """

    /// Images the user added to the post
    static func uploadsRule(_ uploads: [URL]) -> String {
        """
        - THE USER'S IMAGES: the user added these images for this post:
        \(uploads.map { "  - \($0.lastPathComponent): \($0.path)" }.joined(separator: "\n"))
          Open each one with Read and look at it closely (who or what is in it, any text, the mood and colors). Build the video around them as the request says; if the request is just the images, tell their story. Use them in scenes via the assets field with the exact file name. Each also has a cut-out version (subject without its background) the developer can place over a new background.
        """
    }

    /// Directing principles for an app promo film
    static let promoRules = """
    - This is NOT a screenshot slideshow. Build a commercial with a story and rhythm: kinetic typography, number and probability animations, notification cards, countdowns, a matchup scoreboard, pitch/arena atmosphere, particle and flash effects, camera shake, hard cuts.
    - Use screenshots only to prove the product, in at most 1–2 scenes; if possible in a cinematic way such as a zoom-in (ZoomShot) or a 3D tilted phone.
    - The first 1.5 seconds must be a scroll-stopping hook. Last scene is the CTA: app name/icon and store badge.
    """

    /// Directing principles for a free-form video: the user's request is the whole brief
    static let freeformRules = """
    - The user's request is the brief. Follow its format (news report, story, explainer, countdown…), structure, tone and ending literally.
    - This is NOT an ad for the app. Do not mention the app, its features or slogans, do not show screenshots or the app icon, and do not add a store CTA, unless the request explicitly asks for it, and then only where and as much as it asks (e.g. "end with a download-the-app outro" means only the final scene shows the app).
    - Pick the visual grammar of the requested genre (e.g. a news report: lower thirds, breaking-news band (Ticker), live chip, scoreboard, headline cards). Brand colors may drive the palette.
    - The first 1.5 seconds must be a scroll-stopping hook.
    """

    /// Foreign names in voiceover: TTS reads text with the video language's phonetics.
    static func pronunciationRule(_ language: String) -> String {
        """
        - The voiceover is only heard, never shown, and the TTS reads it with \(language) phonetics. Respell foreign proper names (people, players, clubs, brands, places) the way a \(language) speaker would write their correct pronunciation, e.g. in a Turkish video "Jayden Oosterwolde" → "Ceydın Ostervolde", "Mourinho" → "Murinyo", "Szymański" → "Şimanski". Names already read correctly in \(language) stay as they are. On-screen text keeps the original spelling.
        - Write scores, times and abbreviations as they are spoken (e.g. in Turkish "2-1" → "ikiye bir", "90+3" → "doksan artı üç").
        """
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
            "logos": (board.logos ?? []).map { logo in ["name": logo.name, "url": logo.url, "wiki": logo.wiki].compactMapValues { $0 } },
            "people": (board.people ?? []).map { p in ["name": p.name, "url": p.url, "wiki": p.wiki, "edit": p.edit].compactMapValues { $0 } },
            "coverScene": board.coverScene ?? 0,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func storyboardSchema(assetNames: [String], maxHashtags: Int, research: Bool, image: Bool = false, slides: Int = 1) -> [String: Any] {
        var asset: [String: Any] = ["type": "string"]
        if !assetNames.isEmpty { asset["enum"] = assetNames }
        return [
            "type": "object",
            "properties": [
                "title": str,
                "concept": str,
                "scenes": [
                    "type": "array",
                    "minItems": image ? slides : 3,
                    "maxItems": image ? slides : 10,
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
                "logos": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["name": str, "url": str, "wiki": str],
                        "required": ["name"],
                    ],
                ],
                "people": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": ["name": str, "url": str, "wiki": str, "edit": str],
                        "required": ["name"],
                    ],
                ],
                "coverScene": ["type": "integer", "minimum": 0],
            ],
            "required": ["title", "concept", "scenes", "caption", "hashtags", "altText", "postingTip"] + (research ? ["findings", "sources"] : []),
        ]
    }
}
