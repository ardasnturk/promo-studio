# Releasing Promo Studio

Everything up to the irreversible step is scripted. Publishing the GitHub release is always done by hand.

## 0. One-time setup (maintainer)

| What | Where |
|---|---|
| Apple Developer Program membership and a *Developer ID Application* certificate | Xcode → Settings → Accounts → Manage Certificates |
| Notarization credentials | `xcrun notarytool store-credentials promo-studio-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific password>` |
| dmgbuild for the designed DMG window | `pipx install dmgbuild` |
| XcodeGen | `brew install xcodegen` |
| GitHub CLI signed in (`gh auth login`) for the release draft | optional; the script prints the commands otherwise |

`scripts/build-release.sh` signs with team `5JMD3VSD7N` by default; set `TEAM_ID` for another team and
`NOTARY_PROFILE` for a differently named notarytool profile.

## 1. Prepare the version

1. Set `MARKETING_VERSION` in `project.yml`.
2. If user-facing strings changed: build Debug into `./build` and run `python3 scripts/l10n.py --check`.
3. Write `docs/release-notes/<version>.md`.
4. Commit and push.

## 2. Build, sign and notarize

```sh
scripts/build-release.sh
```

regenerates the Xcode project, archives the `PromoStudio` scheme (Release, Developer ID, hardened runtime, secure
timestamp), exports it, verifies the signature, notarizes and staples the app, builds `dist/PromoStudio-<version>.dmg`
with the designed window (`scripts/dmg/`), signs, notarizes and staples the DMG and writes its SHA-256 next to it.

Check by hand on a second Mac or a fresh user account: open the DMG (Gatekeeper must not complain), drag the app to
Applications, open it and go through the setup checklist once.

## 3. GitHub release draft + Homebrew cask

```sh
scripts/prepare-release.sh <version>
```

uploads the DMG and its `.sha256` to a **draft** release `v<version>` with the notes from
`docs/release-notes/<version>.md` and writes version and SHA-256 into `Casks/promo-studio.rb`.

The in-app updater (`PromoStudio/Update/`) expects exactly these asset names: `PromoStudio-<version>.dmg` and
`PromoStudio-<version>.dmg.sha256`. It only sees published releases of a public repository.

Then, deliberately:

1. Review the draft on GitHub and press **Publish release**.
2. Commit and push the cask: `git commit -m "Homebrew cask <version>" Casks/promo-studio.rb && git push`.
3. Verify: `brew tap ardasnturk/promo-studio https://github.com/ardasnturk/promo-studio && brew install --cask promo-studio`.

## 4. Promo Templates

Promo Templates is released separately: bump `version` in `templates/package.json` of
[promo-templates](https://github.com/ardasnturk/promo-templates), tag `v<version>` and publish a GitHub release. Promo
Studio compares the installed library's version with the latest release and offers to update it.
