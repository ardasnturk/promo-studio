# Promo Studio control API (v1)

Promo Studio runs a small, token-protected HTTP/1.1 server bound to `127.0.0.1` only, so that local clients on the same Mac (the Remote Code Mac app) can control Promo Studio remotely. Remote Code relays requests from the iPhone to this server over an encrypted channel. Promo Studio is not directly reachable over the network.

## Discovery and authentication

- On launch, Promo Studio starts the server on a random port and writes this file (permissions `0600`):
  `~/Library/Application Support/Promo Studio/control.json`
  ```json
  {"version": 1, "port": 51234, "token": "<64 hex>", "pid": 4242}
  ```
- The token is regenerated on every launch. The file is deleted when Promo Studio quits; if the file exists but no connection can be made, Promo Studio is not running.
- Every request must include an `Authorization: Bearer <token>` header. If it is missing or wrong, the server returns `401`.

## General rules

- Bodies are JSON (`Content-Type: application/json`), dates are ISO 8601, IDs are UUID strings (uppercase).
- Errors: an appropriate HTTP status and `{"error": "<user-facing message>"}`.
- Long-running jobs (analysis, storyboard, production, render, publishing) return `202 {"ok": true, "jobId": "<id>"}` immediately; progress arrives via `/v1/events`, and the result shows up as a state change.

## Endpoints

### `GET /v1/state`
The full app state. The phone fetches it on first launch and on every `changed` event.

```jsonc
{
  "version": 1,
  "revision": 17,                 // increments on every data change
  "projects": [ProjectDTO],
  "posts": [ContentPost],         // Promo Studio's Codable ContentPost, as is (+ a "media" field)
  "accounts": [InstagramAccount],
  "libraries": [LibraryDTO],
  "jobs": {"<postId|projectId>": {"message": "...", "progress": 0.42, "log": ["last 20 lines"], "kind": "render", "startedAt": "<ISO 8601>", "estimatedEnd": "<ISO 8601>"}},
  "problem": Problem | null,      // the failure in the Mac's alert, explained (below)
  "health": [{"id", "title", "status", "detail", "required"}],  // setup checklist; status: ready, missing, notSetUp, warning
  "settings": {"loginMode", "metaAppId", "hasAppSecret", "contentLanguage", "voiceoverEnabled", "defaultTheme", "maxHashtags"},
  "languages": [{"id": "en", "label": "English"}],
  "themes": [{"id": "hype", "label": "..."}]
}
```

- `ProjectDTO`: `{id, name, accountId, logo, analysis, assets: [{fileName, label, isFramed, language}]}`. `analysis` is Promo Studio's `ProjectAnalysis` struct (features, suggestions, brand colors). `logo` and assets are `/v1/media/...` paths.
- `LibraryDTO` (template libraries such as Promo Templates): `{id, name, compositions, skills: [{name, description, argumentHint, suggestedProjectId}], ideas: [VideoIdea], ideaSources: [url]}`. `suggestedProjectId` is the project the skill's name points to (may be null). `ideas` is the latest trend research (`generateIdeas`), not persisted: `{title, hook, flow, why, skill, difficulty, request}`. Videos made from a library are ordinary posts with an `external` field.
- A post's `projectId` is null for a standalone video. `accountId` is the Instagram account chosen for the post (it overrides the project's) and, once published, the account it went to.
- Each post additionally has `"media": {"video": "/v1/media/posts/<id>/video.mp4" | null, "cover": "/v1/media/posts/<id>/cover.jpg" | null, "image": "/v1/media/posts/<id>/image.jpg" | null, "slides": ["/v1/media/posts/<id>/image.jpg", "/v1/media/posts/<id>/image-2.jpg", …]}` (`slides`: every picture of an image post in order; one for a single image, empty for a video).
- `placement` is where the post goes on Instagram: missing or `feed` (a Reel for a video, a photo or carousel for an image) or `story` (no caption, gone after 24 hours; a carousel goes out as one story per slide). `canPostToFeed` is false for a 9:16 image, which can only be a story.
- `format: "image"` marks an image post: a picture made like a directed video (design brief → code → the last frame rendered as `image.jpg`, which is also the cover). `directed.size` is `portrait` (1080×1350), `square` or `story` (1080×1920). `directed.slides` (2–10) makes it a carousel: one storyboard scene per slide, rendered as `image.jpg`, `image-2.jpg`… Instagram fetches pictures from a public URL, so while one is published Promo Studio serves it through a temporary Cloudflare quick tunnel (`cloudflared`, no account; random trycloudflare.com address, closed right after). `settings.canPostPictures` says whether cloudflared is installed.
- `uploads`: file names of the images the user added to the post (Claude looks at them; they are usable in scenes, each with a cut-out).
- `directed.storyboard.people`: real people the video shows (`{name, wiki?, url?, edit?, useOriginal?, editError?}`); Promo Studio downloads a photo of each and cuts them out of the background. `edit` is how Codex (image generation, on the user's ChatGPT plan) changes the photo; the video uses the edit unless `useOriginal`. `media.people` lists their photos: `[{name, original, edited}]` (media paths `posts/<id>/people/<file>`, null when missing). `settings.editPhotos` says whether Codex can edit photos on this Mac.
- `problem`: why the post's last step failed (`lastError` holds the same message):
  `{code, title, message, fix?, details?, kind?, subject?}`. `fix` is `retry` (run the failed step again), `repair` (Claude fixes the video code from the render error), `withoutVoiceover`, `reconnect` (Instagram session), `settings` or `setup` (the Mac's checklist). `details` is the raw output.

### `GET /v1/events` (Server-Sent Events)
The connection stays open. Events:

| event | data | Meaning |
|---|---|---|
| `changed` | `{"revision": 18}` | Data changed; fetch `/v1/state` again (sent at most twice per second) |
| `job` | `{"id", "message", "progress", "kind", "startedAt", "estimatedEnd"}` | Progress of a running job (at most 4 times per second) |
| `jobEnded` | `{"id"}` | Job finished |
| `finished` | `{"id", "kind", "title", "notice", "postId", "error", "problem"}` | A job ended. `notice` (optional) says what is worth telling the user: `videoReady`, `imageReady`, `storyboardReady`, `published` or `failed` (with `error`, the readable message, and `problem`); cancelled jobs send nothing. Remote Code turns it into a notification |
| `alert` | `{"title", "message", "problem"?}` | Phone counterpart of the alert shown on the Mac; `problem` when it is a failure |
| `ping` | `{}` | Every 20 s; keeps the connection alive |

**Remaining time.** `kind` is one of `analyze`, `script`, `storyboard`, `produce`, `revise`, `render`, `caption`, `translate`, `generate`, `ideas`, `capture`, `publish`, `other`. `estimatedEnd` is missing until Promo Studio can estimate: from the render progress rate, or from the median duration of the last jobs of the same kind (`timings.json`, after two successful jobs).

### `GET /v1/media/<path>`
File bytes. `Range: bytes=a-b` is supported (`206 Partial Content`), with `Content-Range` and `Accept-Ranges: bytes` in the response. Paths:
- `posts/<postId>/video.mp4`, `posts/<postId>/cover.jpg`
- `projects/<projectId>/assets/<file>` (including the logo)

Remote Code should fetch videos with `Range` in chunks of at most 4 MB (the message limit on the encrypted channel).

### `POST /v1/actions/<name>`
JSON body. The response is `{"ok": true}`, or `202 {"ok": true, "jobId"}` for long jobs; actions that create a new post also return `postId`.

| Name | Body | Notes |
|---|---|---|
| `createPost` | `projectId, featureId?, suggestionId?, theme?, seconds, notes?, autoRender?, language?` | Quick template video |
| `createScriptPost` | `projectId, prompt, research, featureId?, theme?, seconds, language?` | Quick template from a custom request (auto-render off) |
| `createDirectedPost` | `projectId?, prompt, research, featureId?, seconds, language?, voiceover, style?, accountId?, format?, size?, slides?, uploads?` | Claude-directed video, storyboard first. `style`: `promo` (default, app promo film) or `freeform` (any video the prompt describes; the app only appears if asked). Without `projectId` a standalone video (always free-form, about no app). `format: "image"` makes an image post of `size`; `slides` (2–10) a carousel. `uploads`: IDs from `uploadImage`; `prompt` may then be empty |
| `uploadImage` | `data` (base64, ≤ ~3 MB) | Sends one image ahead of `createDirectedPost`; returns `uploadId`. Unused uploads are removed after a day |
| `fix` | `postId, fix` | Applies a fix of the post's `problem` that runs on the Mac: `retry`, `repair` or `withoutVoiceover` |
| `setPersonPhoto` | `postId, name, useOriginal` | Which photo of a person the video uses: the downloaded one or Codex's edit |
| `editPersonPhoto` | `postId, name, instruction?` | Codex edits the person's photo again; `instruction` replaces the current one (job id = `postId`) |
| `checkHealth` | — | Checks the setup again; the result is in `health` |
| `produce` | `postId, voiceover` | Approve the storyboard, have the video coded and render it |
| `revise` | `postId, instruction, renderAfter` | Storyboard (+ code) for a promo film, script for a template |
| `restoreRevision` | `postId, revisionId` | |
| `updatePost` | `postId, title?, caption?, hashtags?, altText?, storyboard?, accountId?` | Manual edit; `storyboard` is a full `Storyboard` object. `accountId`: the Instagram account for this post (""/null: the project's) |
| `rewriteCaption` | `postId, instruction` | |
| `render` | `postId` | |
| `setCover` | `postId, sec` | Use the frame at `sec` seconds as the cover; it is also sent to Instagram as the Reel's cover. Posts carry the current one as `coverSec` |
| `cancel` | `id` | Cancels a post or project job |
| `deletePost` | `postId` | |
| `publish` | `postId, placement?` | Publish right away: a video as a Reel or story, an image as a photo, carousel or story(s). `placement` (`feed` or `story`) is saved on the post |
| `schedule` | `postId, at, placement?` | |
| `unschedule` | `postId` | |
| `setPlacement` | `postId, placement` | `feed` or `story` |
| `analyze` | `projectId` | Analyze (or re-analyze) the project |
| `setAccount` | `projectId, accountId?` | The project's Instagram account |
| `loginInfo` | — | `{"mode", "authorizeURL", "redirectURI"}`: the phone opens OAuth in its own browser |
| `connectToken` | `token, expiresIn?` | Access token returned by OAuth; Promo Studio exchanges it for a long-lived one and adds the accounts |
| `connectCode` | `code` | For Instagram login (code flow) |
| `refreshAccounts` | — | Also adds newly connected accounts |
| `disconnect` | `accountId` | |
| `refreshMetrics` | — | |
| `dismissAlert` | — | Dismisses the alert on the Mac |
| `generateFromSkill` | `libraryId, skill, request?, projectId?, accountId?` | Claude Code runs a library's video template (skill) and renders the video. Without `projectId` the video belongs to no project. Returns `postId` |
| `createTemplate` | `libraryId, prompt` | Claude Code adds a new video template (skill + reference composition) to the library from the description, then rescans it (job id = `libraryId`) |
| `generateIdeas` | `libraryId, focus?` | Trend research for video ideas; results arrive in the library's `ideas` (job id = `libraryId`) |

## Connecting an account from the phone

1. Get `authorizeURL` and `redirectURI` with `loginInfo`.
2. The phone opens the URL with `ASWebAuthenticationSession`; since `redirectURI` is HTTPS, use `callback: .https(host:path:)`.
3. In Facebook mode the token is in the redirect URL's `#access_token=...&expires_in=...` fragment → `connectToken`. In Instagram mode, `?code=...` → `connectCode`.

## Security

- The server binds to loopback only; no endpoint responds without the token.
- The token and `control.json` are written with permissions that only the user can read.
- The media endpoint serves only post and project files from Promo Studio's own data folder (`..` and absolute paths are rejected).
