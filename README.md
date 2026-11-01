<p align="center"><img src="docs/icon.png" width="128" height="128" alt="Promo Studio icon"></p>

<h1 align="center">Promo Studio</h1>

<p align="center">Promo videos for the apps you build, <b>written and directed by Claude Code</b>.</p>

<p align="center">
  <a href="https://github.com/ardasnturk/promo-studio/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/ardasnturk/promo-studio?label=release"></a>
  <a href="https://github.com/ardasnturk/promo-studio/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/ardasnturk/promo-studio/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

<p align="center"><b>English</b> · <a href="README.tr.md">Türkçe</a></p>

> **Promo Studio works with Claude Code, Remotion, Gemini and Instagram.** It is
> an independent open-source project and is **not affiliated with, endorsed by
> or sponsored by Anthropic, Remotion, Google or Meta**. You are responsible for
> using those services in line with their terms.

Promo Studio is a Mac app that turns your app's source code into short vertical
videos (Reels, TikTok, Shorts). It reads your project, writes a storyboard from
your prompt — researching facts on the web when needed — has Claude code a
custom [Remotion](https://www.remotion.dev) video for it, renders it with
voiceover and posts or schedules it on Instagram.

Promo Studio drives **your own `claude` CLI**, signed in with your own account.
There is no Promo Studio server, account or telemetry: your code, keys and
videos stay on your Mac.

## Features

* **Promo films directed by Claude** — a scene-by-scene storyboard from your
  prompt, approved by you, then coded as its own Remotion video with kinetic
  type, counters, phone shots and sound effects; revise it in plain words.
* **Quick templates** — one-click videos from your app's features and
  screenshots when you don't need a whole film.
* **Research with sources** — Claude verifies current facts (dates, line-ups,
  prices) with web search before they go on screen, and shows its sources.
* **Voiceover and music** — Gemini text-to-speech (optional) fitted to the
  scenes, and a royalty-free background beat.
* **Instagram** — publish now or schedule Reels through the official APIs,
  then follow views and reach. Optional: **Save Video…** exports the MP4.
* **Ten languages** — videos and the app itself in English, Türkçe, Deutsch,
  Español, Français, Italiano, Português, 日本語, 한국어 and 简体中文.
* **Menu bar first** — a panel with what needs you, jobs in progress and the
  next posts; scheduled posts go out while the studio window is closed.
* **From your iPhone** — with [Remote Code](https://github.com/ardasnturk/remote-code),
  create, approve and post videos from your phone.

## Contents

* [Quick start](#quick-start)
* [Requirements](#requirements)
* [Install](#install)
* [Making a promo film](#making-a-promo-film)
* [Quick templates](#quick-templates)
* [Instagram](#instagram)
* [Voiceover, music and languages](#voiceover-music-and-languages)
* [Promo Templates](#promo-templates)
* [The menu bar](#the-menu-bar)
* [Remote control from your iPhone](#remote-control-from-your-iphone)
* [Updates](#updates)
* [Troubleshooting](#troubleshooting)
* [Privacy and security](#privacy-and-security)
* [FAQ](#faq)
* [Building from source](#building-from-source)
* [Contributing](#contributing)
* [License](#license)

## Quick start

1. **Install Promo Studio** — download the DMG from
   [Releases](https://github.com/ardasnturk/promo-studio/releases/latest), drag
   Promo Studio into Applications and open it. Its icon appears in the menu bar
   and the studio window opens.
2. **Finish the setup checklist** — it opens by itself when something is
   missing: Claude Code (installed and signed in) and Node.js 20+. Click
   **Install** next to Remotion; it takes a few minutes the first time.
3. **Add your app** — **Add Project Folder…** in the sidebar and choose your
   app's source folder. Claude analyzes it: features, audience, brand colors
   and screenshots.
4. **Write a prompt** — on the project, **Write Prompt…**: "a 20-second launch
   film for the new widgets". Claude writes the storyboard; approve it, and the
   video is coded and rendered.
5. **Post it** — **Save Video…** or **Share**, or connect Instagram once and
   publish or schedule from the studio.

Voiceover and Instagram are optional; see [docs/SETUP.md](docs/SETUP.md) for
the Gemini key and the Meta app.

## Requirements

| | |
|---|---|
| Mac | macOS 15 Sequoia or later, Apple silicon or Intel |
| Claude Code | The official CLI installed and signed in with **your own Claude account** (`claude auth status`) |
| Node.js | 20 or later; Promo Studio installs Remotion and uses its bundled ffmpeg |
| Voiceover | Optional. A [Gemini API key](https://aistudio.google.com) (free tier: about 10 requests a day per model, one per video) |
| Instagram | Optional. A Business or Creator account and your own Meta developer app |
| Localized screens | Optional. Xcode with the iOS Simulator |

## Install

Download the notarized `PromoStudio-<version>.dmg` from
[GitHub Releases](https://github.com/ardasnturk/promo-studio/releases), or use
Homebrew:

```sh
brew tap ardasnturk/promo-studio https://github.com/ardasnturk/promo-studio
brew install --cask promo-studio
```

Open Promo Studio. On first launch the **setup checklist** shows what is
missing, with links and commands (**Help → Setup Checklist…** opens it again).
Step-by-step instructions, including the Meta app and the Gemini key:
**[docs/SETUP.md](docs/SETUP.md)**.

## Making a promo film

On a project, **Write Prompt…** (or **Customize… → My Own Request**):

1. **Storyboard** — Claude turns your prompt into a director's storyboard:
   concept and visual language, a visual and motion note per scene, on-screen
   text, voiceover, sound effects and which of your screenshots to use. With
   **Let Claude research the web** on, it checks current facts first and lists
   its sources. Edit the storyboard by hand or ask for changes in **Revise with
   Claude**.
2. **Approve and produce** — the voiceover is generated (scene lengths follow
   the audio), Claude codes the video in Remotion, checks its own work with
   `tsc` and rendered frames, and Promo Studio renders it. **Without
   Voiceover** skips the voiceover.
3. **Revise** — "the hook headline runs off the edge, center it". Claude
   updates the storyboard and only the code that needs to change, and the video
   renders again. Every earlier version is kept; **Restore This Version** brings
   one back.

Claude works with the motion kit in `RemotionTemplate/src/kit`
([KIT.md](RemotionTemplate/KIT.md)) and may write only to that video's folder
(`Edit(src/videos/<id>/**)`) and run only `npx tsc` and `npx remotion still`.
If a template library has a folder named after your project (for example
`src/Acme`), Claude reads it as your brand kit.

## Quick templates

Each analyzed project lists its features and content ideas. **Quick Video**
makes a 15-second video from a feature in one click; **Customize…** lets you
pick the theme, length, language and notes. In this mode Claude writes the
script for a ready-made template (hook, features, numbers, call to action) and
Promo Studio renders it with your screenshots and brand colors.

## Instagram

Promo Studio uses the official Instagram APIs; no passwords are stored and
tokens live in the Keychain. Connecting is optional.

* **Facebook Login** (default) adds every Instagram account linked to the
  Facebook Pages you manage, in one go. **Instagram Login** works without a
  Page.
* Both need your own Meta developer app; it can stay in development mode for
  your own accounts. Permissions and settings:
  [docs/SETUP.md](docs/SETUP.md#instagram).
* Each project posts with its own account (picker in the project header).
  Videos are uploaded directly; no public server is needed.
* With the App Secret entered, tokens are extended to 60 days and renewed
  before they expire.

## Voiceover, music and languages

* Claude writes one voiceover line per scene (with a tone tag such as
  `[excited]`); all lines are spoken in a single Gemini TTS request, split at
  the pauses and fitted to the scenes. When the daily Gemini quota is used up,
  Promo Studio says when it resets and you can produce without voiceover.
* The background track is a locally generated, royalty-free 120 BPM beat that
  ducks under the voice.
* Each video is made in its own language; **Copy in Another Language** adapts
  the texts, voiceover, caption and hashtags and renders again.
* The app follows your Mac's language (the same ten languages as Remote Code).
  Choose another one in System Settings → General → Language & Region →
  Applications.
* **Localized Screens…** opens your app in the iOS Simulator in every language
  and captures the screens Claude found in your code (UI tests, launch
  arguments, deep links).

## Promo Templates

[Promo Templates](https://github.com/ardasnturk/promo-templates) is Promo
Studio's template library: ready-made formats (physics loops, puzzles solved by
a real solver, wordless machines, relaxing exercises, chat stories) and the
Claude Code skills that make new videos of each kind. Promo Studio offers to
install it and keeps it up to date; any Remotion project with Claude Code
skills can be added with **Add Library…**.

* **Generate…** — pick a skill and write a request; Claude runs it in the
  library, writes, checks and renders the video, and Promo Studio imports it
  with a caption.
* **Research Trends** — the ideas skill researches trends and proposes concepts;
  **Generate This** starts the matching skill.
* **Render Again with These Parameters** — change the props of a template video
  and render without Claude.

## The menu bar

Promo Studio lives in the menu bar. Its panel shows what needs you (storyboards
to approve, failed posts, setup), what is in production with progress, the next
scheduled posts and a box to start a new promo film. The Dock icon appears only
while the studio or Settings window is open. **Settings → General → Open at
login** starts it with your Mac, so scheduled posts go out on time.

## Remote control from your iPhone

With [Remote Code](https://github.com/ardasnturk/remote-code) on the same Mac,
its iPhone and iPad app shows a **Promo Studio** tab: projects, prompt to video,
storyboards and revisions, video playback, captions, posting, scheduling and
Instagram sign-in — over Remote Code's end-to-end encrypted connection. Remote
Code also notifies you on the Mac and the phone when a video is ready, a
storyboard waits for approval, a post went out or a job failed, and running
jobs show their remaining time. Promo
Studio serves a token-protected API on `127.0.0.1` only; see
[docs/CONTROL_API.md](docs/CONTROL_API.md).

## Updates

Promo Studio checks GitHub for a new release once a day (Settings → Updates).
**Install and Relaunch** downloads it, checks its SHA-256 checksum, Apple
notarization and developer signature, replaces the app and opens the new
version. Template libraries that come from GitHub are checked too and updated
with git when they have no local changes. Homebrew users can also run
`brew upgrade --cask promo-studio`.

## Troubleshooting

**Claude Code or Node.js is "not found" although it is installed.** Apps opened
from Finder don't get your Terminal's `PATH`. Promo Studio reads it from your
login shell and also looks in `/opt/homebrew/bin`, `/usr/local/bin` and
`~/.local/bin`; make tools from a version manager available in `~/.zprofile`,
then **Check Again** in the setup checklist.

**macOS asks for Keychain access.** Choose **Always Allow** once. Release
builds keep that permission across updates.

**"Gemini quota is used up".** The free tier allows about 10 voiceover requests
a day per model. Produce **Without Voiceover**, pick another TTS model in
Settings, or wait for the reset time Promo Studio shows.

**No Instagram accounts after login.** Promo Studio says what is missing — a
permission, a Page or account you didn't select, or an account that isn't a
Business/Creator account linked to a Page. See
[docs/SETUP.md](docs/SETUP.md#if-something-goes-wrong).

## Privacy and security

* **No server, no telemetry.** Promo Studio talks only to your `claude` CLI
  (and through it, Anthropic), Google's Gemini API if you add a key, Meta's
  Graph API for Instagram, GitHub for updates, and the web pages Claude reads
  during research.
* **Secrets** — Instagram tokens, the Meta App Secret and the Gemini key are
  kept in the Keychain, never in files or prompts.
* **Narrow tools for Claude** — analysis and writing are read-only; video coding
  may only write that video's folder.
* **Local API** — the remote-control API listens on `127.0.0.1` only and needs
  a random bearer token stored with mode 0600.
* **Data** — `~/Library/Application Support/Promo Studio` (projects, posts,
  renders). Nothing else, nowhere else.

Please report vulnerabilities privately through *Security → Report a
vulnerability* ([SECURITY.md](SECURITY.md)).

## FAQ

**Does Promo Studio need a Claude subscription?**
It needs whatever your Claude Code CLI needs — a Claude account with Claude
Code access or an Anthropic API key. Video coding uses noticeably more of it
than a quick template. Promo Studio itself is free.

**Is Remotion free to use?**
Remotion has its own license: free for individuals, non-profits and companies
with up to 3 employees; larger companies need a
[company license](https://www.remotion.dev/license).

**Does my code leave my Mac?**
Only the way it already does with Claude Code: the CLI talks to Anthropic as
usual. Rendering happens on your Mac.

**Can I post somewhere other than Instagram?**
Save the MP4 with **Save Video…** or **Share** and post it anywhere; direct
publishing is Instagram only for now.

**Scheduled posts didn't go out.**
They are published by the app, so it has to be running (the menu bar is
enough). If the Mac was asleep, the post goes out when it wakes.

**How do I uninstall?**
Quit Promo Studio and delete it (or `brew uninstall --zap --cask
promo-studio`). Remove `~/Library/Application Support/Promo Studio` and the
"Promo Studio" item in Keychain Access for a clean slate.

## Building from source

```sh
git clone https://github.com/ardasnturk/promo-studio.git && cd promo-studio
brew install xcodegen && xcodegen generate
open PromoStudio.xcodeproj          # Xcode 16 or later; scheme PromoStudio
```

* `PromoStudio/` — the app: `App` (state, jobs, scheduler), `Services`
  (Claude Code, Remotion, Instagram, Gemini, control API), `Views`.
* `RemotionTemplate/` — the video template and motion kit Claude codes with.
* `CaptureRunner/` — XCUITest runner for localized screens.
* Builds are ad-hoc signed; to keep Keychain permissions across rebuilds, sign
  with your own team in `Config/Signing.local.xcconfig`.
* Releases: [docs/RELEASE.md](docs/RELEASE.md). Changes:
  [CHANGELOG.md](CHANGELOG.md). Translations: `l10n/` and
  `python3 scripts/l10n.py --check`.

No third-party Swift dependencies.

## Contributing

Issues and pull requests are welcome — please read
[CONTRIBUTING.md](CONTRIBUTING.md) and the [code of conduct](CODE_OF_CONDUCT.md)
first. New motion-kit components and template skills are great first
contributions. Security problems: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Arda Şentürk. Promo Studio renders with
[Remotion](https://www.remotion.dev), which has its
[own license](https://www.remotion.dev/license).

"Claude" and "Claude Code" are trademarks of Anthropic, PBC; "Instagram" and
"Facebook" of Meta Platforms, Inc.; "Gemini" of Google LLC; "Remotion" of
Remotion AG. They are used here only to describe compatibility.
