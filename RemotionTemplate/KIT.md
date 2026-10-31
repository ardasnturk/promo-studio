# Promo Studio motion kit

Every custom video is the `Video` component in `src/videos/<CompositionId>/Video.tsx` and receives `StudioProps`. Import components from `../../kit`. See `src/kit/example/ExampleVideo.tsx` for an example.

## Props (`StudioProps`)

| Field | Description |
|---|---|
| `brand` | `appName`, `primary`, `accent`, `background` (hex), `logo?` (public path), `storeLabel?` |
| `lang` | Language code. Pass `lang={lang}` to the root `AbsoluteFill`. |
| `fps`, `durationInFrames` | Totals for the whole video. Promo Studio computes them. |
| `scenes[i]` | `from`, `durationInFrames` (fitted to the voiceover), `text` (on-screen text, `*emphasis*`), `visual` (director's note), `audio?`, `assets` (public paths) |

Do not change scene timings; the voiceover was generated for them. Sequence scenes with `Timeline`; each scene's audio plays automatically.

## Components

**Timing**
- `Timeline({scenes, render, overlap})`: sequences scenes and plays their audio. Inside `render(i, scene)`, `useCurrentFrame()` counts from the start of the scene.
- `Sfx({sound, at, volume})`: plays a sound effect. Sounds: `whoosh`, `whip`, `switch`, `ding`, `click`, `pageTurn`, `shutter`, `notification`, `boom`, `dramatic`, `recordScratch`, `yippee`, `wow`.

**Motion (hooks)**
- `useEnter(delay, bouncy)`: spring from 0 to 1.
- `useExit(duration, frames)`: exit at the end of a scene.
- `useProgress(start, end)`: 0 to 1 between two frames.
- `usePunch(at, strength)`: scale punch on a beat.
- `useShake(from, to, px)`: camera shake.
- `useDrift(duration)`: slow push-in.

**Text**
- `Kinetic({text, size, accent, family, animation: 'rise'|'pop'|'slam', boxed, glow, align})`: word-by-word headline.
- `Typewriter`: typewriter effect.
- `Caption`: caption box.
- `fonts`: `display` (Anton), `condensed` (Bebas), `heading` (Montserrat), `body` (Inter), `mono` (Space Grotesk).

**Images**
- `Phone({src, width, framed, tilt, float, glow, scroll})`: shows a screenshot in a phone frame. Pass `framed` for store images that already have a frame.
- `ZoomShot({src, width, height, focusX, focusY, zoom})`: zooms into part of a screen.
- `AppIcon({src, size, glow})`: app icon.

**Data**
- `Counter`: counting number.
- `ProbabilityBar({values, colors, labels})`: three-part probability bar.
- `BarChart`: bar chart.
- `Countdown`: countdown.
- `Badge({code, primary, secondary})`: badge drawn from colors.
- `Matchup({home, away})`: head-to-head board.

**Interface**
- `Notification({title, body, icon})`: notification card.
- `Chip({label, color, pulse})`: short label.
- `GlassCard`: glass card.
- `Ticker`: scrolling news ticker.
- `StaggerList`: list that appears item by item.

**Backgrounds and effects**
- Backgrounds: `GradientBg`, `Spotlight`, `GridFloor`, `Pitch` (football pitch).
- Effects: `Particles`, `Burst` (confetti), `Flash` (white flash), `Vignette` (edge darkening; put it on top).

If the kit is not enough, write your own component inside the video's folder. Do not change kit files.

## Rules

- **Format:** 1080×1920.
  - Safe area: 80 px from the sides, 120 px from the top and bottom.
  - Headlines ≥ 84 px, supporting text ≥ 44 px.
- **Animation:** Use only `useCurrentFrame`, `interpolate` and `spring`. No CSS animations or transitions. No `Math.random`; use `random(seed)` for randomness.
- **Text:** Write uppercase text in uppercase in the source itself (e.g. Turkish `İ`, `Ş`, `Ğ`). Do not use `textTransform: uppercase`; it breaks letters such as Turkish i/İ.
- **Images:**
  - Use only `scene.assets`, `brand.logo` and the kit's drawings.
  - Do not download images from the internet.
  - Do not draw official club, league or brand logos. Use `Badge` and colors instead.
- **Scene structure:**
  - Not every scene has to be a screenshot. Build a promo film with kinetic typography, data animation, notifications, counters, pitches and similar scenes.
  - Screenshots prove the product; the video is not a slideshow.
- **Sound effects:** Keep them below the voiceover. Use a `volume` between 0.3 and 0.5 and at most 2 effects per scene.
