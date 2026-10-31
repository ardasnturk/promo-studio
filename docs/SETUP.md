# Setting up Promo Studio

**English** · [Türkçe](SETUP.tr.md)

Promo Studio runs tools that are installed on your Mac. On launch it checks them and opens a **setup checklist** when
something required is missing. You can open it at any time from **Help → Setup Checklist…**.

| | Needed for | Required |
|---|---|---|
| [Claude Code](#claude-code) | Analysis, scripts, storyboards, coding the videos | Yes |
| [Node.js 20+](#nodejs-and-remotion) | Remotion, the video engine | Yes |
| [Remotion](#nodejs-and-remotion) | Rendering videos (installed by Promo Studio) | Yes |
| git | Installing and updating Promo Templates | No |
| Xcode | Localized screens from the Simulator | No |
| [Gemini API key](#gemini-voiceover) | Voiceover | No |
| [Instagram](#instagram) | Publishing and scheduling | No |
| [Promo Templates](../README.md#template-libraries-and-promo-templates) | Ready-made formats and skills | No |

Without the optional items you can still make videos: without a Gemini key they have no voiceover, and without
Instagram you save them (**Save Video…** in the studio) and post them yourself.

## Claude Code

1. Install Claude Code: <https://claude.com/claude-code>.
2. Sign in once in Terminal:

   ```bash
   claude auth login
   ```

3. Check it: `claude auth status` should show `"loggedIn": true`.

Promo Studio calls your own `claude` CLI with your own account; usage counts toward your Claude plan or API usage.

## Node.js and Remotion

1. Install Node.js 20 or later from <https://nodejs.org>, or with Homebrew:

   ```bash
   brew install node
   ```

2. In the setup checklist, click **Install** next to **Remotion**. It copies the video template to
   `~/Library/Application Support/Promo Studio/remotion` and runs `npm install` (a few minutes the first time).

Promo Studio uses the `ffmpeg` that comes with Remotion, so a separate ffmpeg install is not needed.

**"not found" although the tool is installed:** apps opened from Finder don't inherit your Terminal's `PATH`. Promo
Studio reads it from your login shell (`zsh -l`) and also looks in `/opt/homebrew/bin`, `/usr/local/bin` and
`~/.local/bin`. If a tool lives elsewhere (for example a version manager that is only set up in `.zshrc` for interactive
shells), make it available in `~/.zprofile` too, then click **Check Again**.

## Gemini voiceover

1. Create an API key in [Google AI Studio](https://aistudio.google.com) (**Get API key**).
2. Paste it into **Account & Settings → Voiceover & Music → Gemini API Key**. Promo Studio stores it in the Keychain.
   Alternatively, set `GEMINI_API_KEY` in your shell profile.

All voiceover lines of a video are generated in one request. The free tier allows about 10 requests a day per TTS model.
When the quota is used up, Promo Studio shows when it resets; meanwhile you can produce with **Without Voiceover**, or
pick another TTS model in Settings.

## Instagram

Publishing uses the official Instagram APIs through your own Meta developer app. You need it only for publishing,
scheduling and analytics. Promo Studio stores no passwords; tokens are kept in the Keychain.

### 1. Prepare the Instagram account

- The account must be a **Business** or **Creator** account. In the Instagram app: **Settings → Account type and tools →
  Switch to professional account**.
- For **Facebook login** (recommended), link the account to a Facebook Page you manage: in the Page's settings,
  **Linked accounts → Instagram → Connect**. Several Instagram accounts can be linked to several Pages; all of them are
  added in one login.

### 2. Create a Meta app

1. Open <https://developers.facebook.com/apps> and click **Create App**. Choose the options that let you add
   **Facebook Login for Business** (a **Business** type app). Meta changes the wizard from time to time; if it asks for a
   use case, pick the one for managing Instagram content, or **Other**.
2. Add the **Facebook Login for Business** product. In its **Settings**:
   - turn on **Embedded Browser OAuth Login**,
   - add `https://www.facebook.com/connect/login_success.html` to **Valid OAuth Redirect URIs**.
3. Make sure these permissions are available to the app (in development mode they work without App Review for people
   who have a role on the app):
   `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights`, `instagram_manage_comments`,
   `pages_show_list`, `pages_read_engagement`, `business_management`.
4. In **App settings → Basic**, copy the **App ID** and the **App Secret**.

The app can stay in **development mode** for your own accounts: only people with a role on the app (admin, developer,
tester) can log in, which includes you.

### 3. Connect in Promo Studio

1. **Account & Settings → Meta App**: paste the App ID and App Secret. Keep the redirect URI as it is.
2. Click **Log In with Facebook**, sign in, and select the Pages and Instagram accounts to share with the app.
3. Every Instagram account linked to those Pages is added. With the App Secret, the token is extended to 60 days and
   renewed before it expires. **Refresh Accounts** adds accounts you link later without signing in again.
4. On each project, choose the account it posts with (account picker in the project header).

### Instagram login (alternative)

Without a Facebook Page, choose **Instagram login** as the connection type. In the Meta app, add the **Instagram**
product with "API setup with Instagram login", the permissions `instagram_business_basic`,
`instagram_business_content_publish`, `instagram_business_manage_insights`, `instagram_business_manage_comments`, and
Promo Studio's redirect URI (default `https://localhost/promostudio/callback`). In development mode, add your Instagram
account as a tester (**App roles → Roles → Instagram Testers**) and accept the invitation in Instagram.

### If something goes wrong

- **No accounts after login:** Promo Studio says what is missing: a permission from the list above, a Page or account
  you didn't select during login, or an Instagram account that is not a Business/Creator account linked to a Page.
  Fix it and log in again.
- **Permission error while publishing:** usually `instagram_content_publish` was not granted. Log in again and allow
  every requested permission.
- **Token expired:** with the App Secret entered, Promo Studio renews it automatically; otherwise log in again.

## Keychain prompts

macOS asks once before an app reads its Keychain item. Choose **Always Allow**. Builds signed with a stable identity
(release builds, or your own team in `Config/Signing.local.xcconfig`, see [Config/Signing.xcconfig](../Config/Signing.xcconfig))
keep that permission across updates. Ad-hoc builds from source ask again after every build.
