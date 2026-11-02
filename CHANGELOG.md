# Changelog

All notable changes to Promo Studio are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
