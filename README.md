# Promo Studio

**English** · [Türkçe](README.tr.md)

Promo videos for the apps you build, written and directed by Claude Code. Promo Studio is a macOS app that reads your
app's source code, writes a storyboard from your prompt (researching facts on the web when needed), has Claude code a
custom Remotion video for it, renders it with voiceover, and posts or schedules it as an Instagram Reel.

Flow: add a project folder → Claude Code analyzes the code (features, audience, brand colors, screenshots) → write a
prompt or pick a feature/idea → Claude writes the storyboard or script, caption and hashtags → approve or revise →
Remotion renders the video → post now or schedule → follow views and reach.

> Promo Studio drives your own `claude` CLI, signed in with your own account. It is an independent project and is not
> affiliated with Anthropic, Meta or Google.

## Install

Download `PromoStudio-<version>.dmg` from [Releases](https://github.com/ardasnturk/promo-studio/releases/latest) and drag
Promo Studio to Applications, or use Homebrew:

```bash
brew tap ardasnturk/promo-studio https://github.com/ardasnturk/promo-studio
brew install --cask promo-studio
```

The app is signed with Developer ID and notarized by Apple.

## Requirements

- macOS 15+
- [Claude Code](https://claude.com/claude-code) CLI installed and signed in (`claude auth status`)
- Node.js 20+ (Remotion renders the videos; Promo Studio installs Remotion and uses its bundled ffmpeg)
- Optional: a [Gemini API key](https://aistudio.google.com) for voiceover (free tier: about 10 requests a day per model, one per video)
- Optional, for posting: an Instagram **Business** or **Creator** account and your own Meta developer app

To build from source (releases: [docs/RELEASE.md](docs/RELEASE.md)): Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open PromoStudio.xcodeproj
```

On launch, Promo Studio checks these and opens a **setup checklist** when something required is missing (also under
**Help → Setup Checklist…**); it installs Remotion with one click. Step-by-step instructions, including the Meta app and
the Gemini key: **[docs/SETUP.md](docs/SETUP.md)**.

## Videos from your own prompt

On a project, **Video from Your Own Request → Write Prompt…** (or **Customize… → My Own Request**). Two kinds of video:

### Promo film (directed by Claude, default)

A custom-coded promo film for every video, not a screenshot slideshow:

1. **Storyboard:** Claude turns your prompt (researching on the web if enabled) into a scene-by-scene director's
   storyboard: concept and visual language, a visual and motion note per scene, on-screen text, voiceover, sound effects
   and the project images to use. It appears in the studio's **Storyboard** tab; edit it by hand or give instructions in
   **Revise with Claude**.
2. **Approve and produce:** **Approve and Produce Video** generates the voiceover (scene lengths follow the audio),
   Claude codes the video in Remotion (`src/videos/<id>/`), checks its own work with `tsc` and rendered frames, and
   Promo Studio renders it. **Without Voiceover** skips the voiceover.
3. **Revise the video:** give an instruction ("the hook headline runs off the edge, center it"); Claude updates the
   storyboard and only the code that needs to change, and the video is rendered again. Every earlier storyboard and code
   version is kept; **Restore This Version** brings one back.

- **Kit:** Claude uses the motion kit in `RemotionTemplate/src/kit` (kinetic type, counters, probability bars, countdowns,
  badges and match boards, notification cards, phone and zoom shots, pitch, particles, flashes, shakes, sound effects);
  the guide is `RemotionTemplate/KIT.md`. When the kit is not enough, Claude writes its own component in the video's folder.
- **Brand kit:** if a template library has a folder with the project's name (e.g. `src/Acme` for the Acme project),
  Claude reads it and the library's `CLAUDE.md` rules as a brand kit; its `public/<project>` images are copied in. The
  library is never written to.
- **Permissions:** Claude may write only to that video's folder (`Edit(src/videos/<id>/**)`) and may run only `npx tsc`
  and `npx remotion still`.

### Quick template (screenshots)

1. **Prompt:** describe what you want. Optionally pick the feature to highlight; otherwise Claude picks one.
2. **Research:** with **Let Claude research the web** on, Claude verifies current facts (dates, times, line-ups…) with
   WebSearch/WebFetch and uses only what it could verify; findings and sources appear in **Revise with Claude**.
3. **Approve:** automatic rendering is off in this mode; review the script and render it.
4. **Revise:** give instructions in **Revise with Claude**. Only what you asked for changes; earlier versions are kept.

## Instagram

Promo Studio uses the official Instagram APIs (no passwords are stored). Tokens live in the Keychain. Connecting is
optional: without it, **Save Video…** or **Share** in the studio exports the MP4 so you can post it yourself.

With **Facebook Login** (default), the Instagram account must be linked to a Facebook Page you manage; every Instagram
account linked to your Pages is added at once. **Instagram Login** works without a Page. Both need your own Meta app;
the permissions and settings are in [docs/SETUP.md](docs/SETUP.md#instagram). With the App Secret entered, the token is
extended to 60 days and renewed before it expires.

Each project posts with its own account (account picker in the project header). Videos are uploaded directly with
resumable upload; no public server is needed.

## Voiceover, music and languages

- Claude writes one voiceover line per scene (with a tone tag such as `[excited]`). All lines are spoken with a single
  Gemini TTS request, split at the pauses and fitted to the scenes. Audio is regenerated only when the text changes.
  When the daily Gemini quota is used up, Promo Studio says when it resets and you can produce without voiceover.
- The background track is a locally generated, royalty-free 120 BPM beat that ducks under the voice.
- Each video is made in its own language (Türkçe, English, Deutsch, Español, Italiano, Français, Português, 日本語,
  한국어, 简体中文); new projects start in your Mac's language. **Copy in Another Language** adapts the texts, voiceover, caption and hashtags and renders again.
- Promo Studio's own interface is in English, Turkish, German, Spanish, French, Italian, Portuguese (Brazil), Japanese, Korean and Simplified Chinese, the same languages as Remote Code. It follows your Mac's language; to choose another one, use System Settings → General → Language & Region → Applications.

## Localized screens from the Simulator

For app screens that exist in one language only: **Localized Screens…** on a project. Claude Code reads the code (UI
tests, launch arguments, deep links) to find how to open each screen; Promo Studio then opens the app in its own
simulator ("Promo Studio · iPhone") in every language with an XCUITest runner (`CaptureRunner/`) and captures the screens.

## Template libraries and Promo Templates

[Promo Templates](https://github.com/ardasnturk/promo-templates) is Promo Studio's template library: ready-made video
templates (physics loops, puzzles, wordless machines, relaxing and chat stories) and the Claude Code skills that make new
videos of each kind. When no library is connected, Promo Studio offers to install it (git clone, Remotion skills,
`npm install`). Any Remotion project with Claude Code skills can be connected with **Templates → Add Library…**.

- **Generate:** pick a skill and write a request; Claude Code runs it in the library folder, writes, checks and renders
  the video, and Promo Studio imports it and writes a caption. If real-world facts can't be verified, nothing is rendered.
- **Find Ideas:** the ideas skill researches trends and proposes concepts; **Generate This** starts the matching skill.
- **Render Again with These Parameters:** edit the props JSON of a template video and render without running Claude.

## Updates

Promo Studio checks GitHub Releases once a day (**Account & Settings → Updates**). An update is downloaded, verified
against its SHA-256 and code signature, and installed with a click. Template libraries that come from a GitHub
repository are checked against their releases too and updated with git when they have no local changes.

## Remote control from your iPhone

With [Remote Code](https://github.com/ardasnturk/remote-code) on the same Mac, its iPhone app shows a **Promo Studio**
tab: projects, prompt-to-video, storyboards, revisions, video playback, captions, posting and scheduling, and Instagram
sign-in, over Remote Code's end-to-end encrypted connection. Promo Studio serves a token-protected API on 127.0.0.1 only;
see [docs/CONTROL_API.md](docs/CONTROL_API.md).

## Architecture

```
PromoStudio/
  App/AppModel.swift              Central state, job queue, scheduler
  Services/ClaudeCode.swift       `claude -p --json-schema` calls (live activity via stream-json)
  Services/ContentAI.swift        Analysis / script / caption prompts and JSON schemas
  Services/ContentAI+Studio.swift Storyboard writing and revision, video coding prompts
  Services/StudioService.swift    Claude-directed videos: props, entry file, render, code versions
  Services/RemotionService.swift  Installs the template, renders video and cover
  Services/InstagramAPI.swift     OAuth, Reels publishing, insights
  Services/ControlServer.swift    Local control API for Remote Code
  Services/TemplatesService.swift Promo Templates install and updates
  Update/                         App updates from GitHub Releases
  Views/                          SwiftUI screens
RemotionTemplate/                 Video template (AppPromo) and the motion kit (src/kit, KIT.md)
```

- Data: `~/Library/Application Support/Promo Studio/data.json`; secrets (tokens, app secret, Gemini key) in the Keychain.
- The video contract `PromoStudio/Models/VideoSpec.swift` ↔ `RemotionTemplate/src/types.ts` must stay identical.
- Translations: English source strings; the other languages in `l10n/` (`catalog.<language>.json` with catalog keys,
  plus Turkish maps of Swift source strings). `python3 scripts/l10n.py --check` builds the String Catalog after a Debug
  build into `./build` and lists strings that still need a translation in any language.

## Privacy

Promo Studio has no server and no telemetry. It talks to: your `claude` CLI (and through it, Anthropic), Google's Gemini
API for voiceover if you add a key, Meta's Graph API for Instagram, GitHub for update checks, and the web pages Claude
reads during research.

## Known limitations

- Scheduled posts go out while Promo Studio is running (it keeps running in the menu bar when the window is closed). If
  the Mac is asleep, the post goes out when it wakes.
- The Instagram API only allows publishing from Business and Creator accounts.

## License

MIT, see [LICENSE](LICENSE). Promo Studio renders with [Remotion](https://www.remotion.dev), which has its own license:
free for individuals, non-profits and companies with up to 3 employees; larger companies need a company license.
