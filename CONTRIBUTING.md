# Contributing to Promo Studio

Thanks for helping! Promo Studio is a small project with a few firm rules;
reading this first saves everyone a review round.

## Ground rules

* **Promo Studio drives the user's own `claude` CLI.** It never calls the
  Anthropic API directly, never reads `~/.claude*` and never handles Claude
  credentials.
* **No servers, no telemetry, no accounts of our own.** Promo Studio talks only
  to the services the user sets up: their `claude` CLI, Google's Gemini API for
  voiceover, Meta's Graph API for Instagram, GitHub for update checks.
* **Secrets stay in the Keychain** (tokens, App Secret, Gemini key). Never log
  them, never put them in `data.json`, URLs or Claude prompts.
* **Claude gets the narrowest tools that work.** Video coding may only write
  `src/videos/<id>/**` and run `npx tsc` / `npx remotion still`. Widening
  `--allowedTools` needs a good reason in the PR.
* **No third-party Swift dependencies.** The app uses Apple frameworks only.
* Respect the Claude, Instagram and Remotion brands: no logos or wording that
  suggests an official product. Remotion has its own license (see README).

## Getting started

```sh
git clone https://github.com/ardasnturk/promo-studio.git && cd promo-studio
brew install xcodegen
xcodegen generate
open PromoStudio.xcodeproj               # Xcode 16+, scheme PromoStudio
```

Builds are ad-hoc signed by default, so no team is needed. To keep Keychain
permissions across rebuilds, sign with your own team in
`Config/Signing.local.xcconfig` (see `Config/Signing.xcconfig`).

| Directory | What |
|---|---|
| `PromoStudio/App` | `AppModel` (state, jobs, scheduler) and the app / menu bar scenes |
| `PromoStudio/Services` | Claude Code calls and prompts, Remotion, Instagram, Gemini, local control API, templates |
| `PromoStudio/Views` | SwiftUI screens; `Views/Design` holds the shared look (Remote Code family) |
| `PromoStudio/Update` | Updates from GitHub Releases |
| `RemotionTemplate/` | The video template and the motion kit Claude codes with (`KIT.md`) |
| `CaptureRunner/` | XCUITest runner for localized screens from the Simulator |
| `scripts/` | Release, icon and localization tooling |
| `docs/` | Setup, control API, release process |

## Coding conventions

* SwiftUI, `@Observable`, async/await. No force unwraps or `try!` in new code,
  and no new warnings.
* Match the surrounding style: small types, short doc comments, English
  comments, no commented-out code.
* The video contract `PromoStudio/Models/VideoSpec.swift` and
  `RemotionTemplate/src/types.ts` must stay identical.
* User-facing strings are localized in the same languages as Remote Code
  (English, Turkish, German, Spanish, French, Italian, Portuguese (Brazil),
  Japanese, Korean, Simplified Chinese). Write `Text("…")` /
  `String(localized:)` in English, build Debug into `./build`
  (`xcodebuild -scheme PromoStudio -derivedDataPath build build`), add the
  translations to `l10n/catalog.<language>.json` and run
  `python3 scripts/l10n.py --check`.
* After editing `project.yml`, run `xcodegen generate` (the Xcode project is not
  committed).

## Pull requests

1. Open an issue for anything bigger than a bug fix, so we can agree on the
   approach first.
2. Keep PRs focused; one topic per PR.
3. Make sure the app builds, `python3 scripts/l10n.py --check` passes and
   `npx tsc --noEmit` passes in `RemotionTemplate/`.
4. Describe what you changed and how you tested it (which video, which flow).
5. Add an entry to `CHANGELOG.md` under "Unreleased".

By contributing you agree that your contribution is licensed under the
[MIT License](LICENSE).
