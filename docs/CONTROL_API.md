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
  "libraries": [{"id", "name", "skills": [{"name", "description"}]}],
  "jobs": {"<postId|projectId>": {"message": "...", "progress": 0.42, "log": ["last 20 lines"], "kind": "render", "startedAt": "<ISO 8601>", "estimatedEnd": "<ISO 8601>"}},
  "settings": {"loginMode", "metaAppId", "hasAppSecret", "contentLanguage", "voiceoverEnabled", "defaultTheme", "maxHashtags"},
  "languages": [{"id": "en", "label": "English"}],
  "themes": [{"id": "hype", "label": "..."}]
}
```

- `ProjectDTO`: `{id, name, accountId, logo, analysis, assets: [{fileName, label, isFramed, language}]}`. `analysis` is Promo Studio's `ProjectAnalysis` struct (features, suggestions, brand colors). `logo` and assets are `/v1/media/...` paths.
- Each post additionally has `"media": {"video": "/v1/media/posts/<id>/video.mp4" | null, "cover": "/v1/media/posts/<id>/cover.jpg" | null}`.

### `GET /v1/events` (Server-Sent Events)
The connection stays open. Events:

| event | data | Meaning |
|---|---|---|
| `changed` | `{"revision": 18}` | Data changed; fetch `/v1/state` again (sent at most twice per second) |
| `job` | `{"id", "message", "progress", "kind", "startedAt", "estimatedEnd"}` | Progress of a running job (at most 4 times per second) |
| `jobEnded` | `{"id"}` | Job finished |
| `finished` | `{"id", "kind", "title", "notice", "postId", "error"}` | A job ended. `notice` (optional) says what is worth telling the user: `videoReady`, `storyboardReady`, `published` or `failed` (with `error`); cancelled jobs send nothing. Remote Code turns it into a notification |
| `alert` | `{"title": "Something went wrong" \| "Info", "message"}` | Phone counterpart of the alert shown on the Mac |
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
| `createDirectedPost` | `projectId, prompt, research, featureId?, seconds, language?, voiceover, style?` | Claude-directed video, storyboard first. `style`: `promo` (default, app promo film) or `freeform` (any video the prompt describes; the app only appears if asked) |
| `produce` | `postId, voiceover` | Approve the storyboard, have the video coded and render it |
| `revise` | `postId, instruction, renderAfter` | Storyboard (+ code) for a promo film, script for a template |
| `restoreRevision` | `postId, revisionId` | |
| `updatePost` | `postId, title?, caption?, hashtags?, altText?, storyboard?` | Manual edit; `storyboard` is a full `Storyboard` object |
| `rewriteCaption` | `postId, instruction` | |
| `render` | `postId` | |
| `cancel` | `id` | Cancels a post or project job |
| `deletePost` | `postId` | |
| `publish` | `postId` | Publish as a Reel right away |
| `schedule` | `postId, at` | |
| `unschedule` | `postId` | |
| `analyze` | `projectId` | Analyze (or re-analyze) the project |
| `setAccount` | `projectId, accountId?` | The project's Instagram account |
| `loginInfo` | — | `{"mode", "authorizeURL", "redirectURI"}`: the phone opens OAuth in its own browser |
| `connectToken` | `token, expiresIn?` | Access token returned by OAuth; Promo Studio exchanges it for a long-lived one and adds the accounts |
| `connectCode` | `code` | For Instagram login (code flow) |
| `refreshAccounts` | — | Also adds newly connected accounts |
| `disconnect` | `accountId` | |
| `refreshMetrics` | — | |
| `dismissAlert` | — | Dismisses the alert on the Mac |

## Connecting an account from the phone

1. Get `authorizeURL` and `redirectURI` with `loginInfo`.
2. The phone opens the URL with `ASWebAuthenticationSession`; since `redirectURI` is HTTPS, use `callback: .https(host:path:)`.
3. In Facebook mode the token is in the redirect URL's `#access_token=...&expires_in=...` fragment → `connectToken`. In Instagram mode, `?code=...` → `connectCode`.

## Security

- The server binds to loopback only; no endpoint responds without the token.
- The token and `control.json` are written with permissions that only the user can read.
- The media endpoint serves only post and project files from Promo Studio's own data folder (`..` and absolute paths are rejected).
