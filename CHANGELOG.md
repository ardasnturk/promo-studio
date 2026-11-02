# Changelog

All notable changes to Promo Studio are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Videos without a project. A new Videos section makes a video from a prompt
  (directed by Claude, free-form, about no app) or from a library template.
  A project and an Instagram account are both optional and independent.
- Each post can have its own Instagram account, overriding its project's.
- Save Video… in every post's Publish tab, with or without an account.
- New Template…: Claude Code adds a new video template (skill + reference
  composition) to a library from a description.
- Control API: `createDirectedPost` and `generateFromSkill` take an optional
  `projectId` and an `accountId`; `updatePost` takes `accountId`; new
  `createTemplate` action. A post's `projectId` may be null.

### Changed
- Library templates no longer need a project; they used to default to the
  project the skill's name pointed to.

## [1.2.4] — 2026-11-02

### Fixed
- Directed videos drew the opponent's crest as a badge when the director had
  no confirmed image URL for it. Logos may now name an English Wikipedia
  article (`wiki`); its lead image is the fallback when there's no `url` or it
  fails. Every real club, league and brand in the video is listed.

### Added
- Kit `Logo` component; `Matchup` sides take a `logo`.
- Control API: `generateFromSkill` and `generateIdeas` actions; libraries in
  the state carry `compositions`, each skill's `argumentHint` and
  `suggestedProjectId`, and the latest `ideas`.

## [1.2.3] — 2026-11-02

### Fixed
- Splitting the voiceover cut 0.04 s before each line's first loud syllable and
  then trimmed again at -45 dB, so soft opening consonants were lost. Lines now
  start 0.2 s earlier (never inside the previous line), keep a 0.15 s tail and
  only trim silence below -60 dB. Clips cut the old way are voiced again.

## [1.2.2] — 2026-11-02

### Added
- Cover picker in the Publish tab: any frame of the video can be the cover.
- Directed videos show real club, league and brand logos: the storyboard lists
  their image URLs and Promo Studio downloads them (`logos` in the studio props).
- `setCover` control action (`postId`, `sec`); posts carry `coverSec`.

### Fixed
- Reels were posted without a cover frame, so Instagram used the first frame.
  The chosen cover is now sent as `thumb_offset`.
- The automatic cover comes from the scene the director picks (`coverScene`).
- The indeterminate progress bar moved only inside a narrow strip.

## [1.2.1] — 2026-11-01

### Fixed
- Promo Templates was offered for install only while no library was linked, so
  a stale library entry hid the offer. It is now offered whenever Promo
  Templates itself isn't linked, including from Settings → Updates.
- Libraries whose folder is gone show "Folder not found" in Settings → Updates.

## [1.2.0] — 2026-11-01

### Added
- Free-form videos directed by Claude: any video the request describes (news
  report, story, explainer…); the app, its features or a store CTA appear only
  where the request asks. `createDirectedPost` takes `style: "freeform"`.

### Changed
- Voiceover lines respell foreign proper names the way the video's language
  pronounces them (on-screen text keeps the original spelling), and write
  scores and times as spoken.

### Fixed
- The updater quits from the run loop rather than from a main-queue job, which
  would deadlock once the app delegate answers `.terminateLater`.

## [1.1.1] — 2026-11-01

### Fixed
- Installing an update failed with an invalid code signature: the designed DMG
  window set Finder's "hide extension" flag on the app, which the updater's
  strict check rejects. The DMG no longer sets it and the updater ignores it.

## [1.1.0] — 2026-11-01

### Added
- Remaining time for running jobs ("About 3 min left") in the studio, the menu
  bar panel and Remote Code's Promo Studio tab: from the render progress, or
  from how long the last jobs of the same kind took.
- A `finished` event in the control API that tells Remote Code when a video is
  ready, a storyboard waits for approval, a post went out or a job failed —
  Remote Code turns it into notifications on the Mac and the phone.

## [1.0.0] — 2026-11-01

First public release. See [docs/release-notes/1.0.0.md](docs/release-notes/1.0.0.md).
