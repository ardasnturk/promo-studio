import SwiftUI
import WebKit

/// Settings window (⌘,): panes with colored icons like System Settings (same layout as Remote Code).
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, instagram, voiceover, engine, updates
        var id: String { rawValue }
    }

    @State private var pane: Pane = .general

    static let geminiVoices = [
        "Fenrir", "Kore", "Puck", "Charon", "Zephyr", "Aoede", "Leda", "Orus", "Callirrhoe", "Autonoe",
        "Enceladus", "Iapetus", "Umbriel", "Algieba", "Despina", "Erinome", "Algenib", "Rasalgethi",
        "Laomedeia", "Achernar", "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird",
        "Zubenelgenubi", "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat",
    ]

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    title(pane)
                } icon: {
                    IconBadge(symbol: symbol(pane), colors: colors(pane), size: 22)
                }
                .padding(.vertical, 3)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            .background(.thinMaterial)
            Divider()
            VStack(spacing: 0) {
                PaneHeader(symbol: symbol(pane), colors: colors(pane), title: title(pane), subtitle: subtitle(pane))
                detail
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandBackground(intensity: 0.45))
        }
        .frame(width: 800, height: 620)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralSettings()
        case .instagram: InstagramSettings()
        case .voiceover: VoiceoverSettings()
        case .engine: EngineSettings()
        case .updates: Form { UpdatesSection() }
        }
    }

    private func title(_ pane: Pane) -> Text {
        switch pane {
        case .general: Text("General")
        case .instagram: Text("Instagram")
        case .voiceover: Text("Voiceover & Music")
        case .engine: Text("Claude & Video Engine")
        case .updates: Text("Updates")
        }
    }

    private func subtitle(_ pane: Pane) -> Text {
        switch pane {
        case .general: Text("Start at login, content language, hashtags and themes.")
        case .instagram: Text("Accounts each project posts to, and your Meta app.")
        case .voiceover: Text("Gemini voiceover and the background beat.")
        case .engine: Text("The Claude model that writes and directs, and Remotion, which renders.")
        case .updates: Text("New versions of Promo Studio and your template libraries.")
        }
    }

    private func symbol(_ pane: Pane) -> String {
        switch pane {
        case .general: "gearshape.fill"
        case .instagram: "camera.fill"
        case .voiceover: "waveform"
        case .engine: "sparkles"
        case .updates: "arrow.down.circle.fill"
        }
    }

    private func colors(_ pane: Pane) -> [Color] {
        switch pane {
        case .general: [.gray, Color(white: 0.35)]
        case .instagram: [Brand.violet, Brand.pink]
        case .voiceover: [.red, .orange]
        case .engine: [Brand.indigo, Brand.violet]
        case .updates: [.green, Brand.teal]
        }
    }

    static func looksLikeAppSecret(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil
    }
}

/// Launch at login and content defaults
private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if LaunchAtLogin.requiresApproval {
                    HStack {
                        Label("macOS is waiting for your approval in Login Items.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                    .font(.callout)
                }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Promo Studio lives in the menu bar: scheduled posts go out and videos render while the studio window is closed. The Dock icon appears only while a window is open.")
            }

            Section("Content") {
                Picker("Default language", selection: $model.settings.contentLanguage) {
                    ForEach(ContentLanguage.all) { Text($0.label).tag($0.id) }
                }
                Stepper("Up to \(model.settings.maxHashtags) hashtags", value: $model.settings.maxHashtags, in: 1...30)
                Picker("Default theme", selection: $model.settings.defaultTheme) {
                    ForEach(VideoTheme.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Post automatically when rendering finishes", isOn: $model.settings.autoPublishWhenReady)
            }
        }
    }
}

/// Instagram accounts, adding accounts and the Meta app
private struct InstagramSettings: View {
    @Environment(AppModel.self) private var model
    @State private var appSecret = Keychain.get(Keychain.Key.metaAppSecret) ?? ""
    @State private var manualToken = ""
    @State private var showLogin = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.data.accounts.isEmpty {
                    Text("No Instagram accounts connected.").foregroundStyle(.secondary)
                }
                ForEach(model.data.accounts) { a in
                    HStack(spacing: 12) {
                        AsyncImage(url: a.profilePictureURL.flatMap(URL.init(string:))) { $0.resizable() } placeholder: { Circle().fill(.quaternary) }
                            .frame(width: 32, height: 32).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(a.username)").font(.headline)
                            let projects = model.data.projects.filter { $0.accountId == a.userId }.map(\.name)
                            (projects.isEmpty ? Text("Not linked to any project") : Text("Projects: \(projects.joined(separator: ", "))"))
                                .font(.caption).foregroundStyle(projects.isEmpty ? .orange : .secondary)
                            if let exp = a.tokenExpiresAt {
                                Text("Token valid until \(exp.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(exp.timeIntervalSinceNow < 86400 ? .red : .secondary)
                            }
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { model.disconnect(a.userId) }
                    }
                }
                if model.isConnected {
                    Button {
                        Task { await model.refreshAccounts() }
                    } label: {
                        Label("Refresh Accounts", systemImage: "arrow.clockwise")
                    }
                }
            } header: {
                Text("Instagram Accounts")
            } footer: {
                Text("Each project posts to its own account. Choose a project's account in the header of the project screen; videos from a project without an account aren't posted. An account you newly link to a Page is added with \"Refresh Accounts\"; no need to log in again.")
            }

            Section {
                Picker("Connection type", selection: $model.settings.loginMode) {
                    ForEach(InstagramLoginMode.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: model.settings.loginMode) { _, mode in model.settings.redirectURI = mode.defaultRedirectURI }
                Button {
                    showLogin = true
                } label: {
                    Label(model.settings.loginMode == .facebook ? String(localized: "Log In with Facebook") : String(localized: "Log In with Instagram"), systemImage: "person.badge.key")
                }
                .disabled(model.settings.metaAppId.isEmpty || (model.settings.loginMode == .instagram && appSecret.isEmpty))
                HStack {
                    SecureField("…or paste an access token", text: $manualToken)
                    Button("Connect") { Task { await model.connect(withToken: manualToken); manualToken = "" } }
                        .disabled(manualToken.isEmpty)
                }
            } header: {
                Text("Add Account")
            } footer: {
                if model.settings.loginMode == .facebook {
                    Text("Facebook Login adds every Instagram account linked to the Pages you manage in one go. To add a new account, also select its Page on the consent screen. Your Instagram Business/Creator account must be linked to a Facebook Page. You can get a token from Graph API Explorer; if an App ID and App Secret are entered, Promo Studio automatically exchanges it for a 60-day token.")
                } else {
                    Text("Requires a Business or Creator account. You can paste the token you get with \"Generate token\" in the \"API setup with Instagram login\" section of your Meta app.")
                }
            }

            Section("Meta App") {
                TextField(model.settings.loginMode == .facebook ? "App ID" : "Instagram App ID", text: $model.settings.metaAppId)
                SecureField(model.settings.loginMode == .facebook ? "App Secret" : "Instagram App Secret", text: $appSecret)
                    .onChange(of: appSecret) { _, v in
                        Keychain.set(v.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.Key.metaAppSecret)
                        if SettingsView.looksLikeAppSecret(v) { Task { await model.upgradeTokenIfNeeded() } }
                    }
                if !appSecret.isEmpty, !SettingsView.looksLikeAppSecret(appSecret) {
                    Label("This doesn't look like an App Secret. The App Secret is the 32-character code under Settings → Basic in the Meta dashboard (not an access token).", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                TextField("Redirect URI", text: $model.settings.redirectURI)
                TextField("Graph API version", text: $model.settings.graphVersion)
            }
        }
        .sheet(isPresented: $showLogin) {
            InstagramLoginSheet(settings: model.settings) { result in
                showLogin = false
                switch result {
                case let .code(code): Task { await model.connect(withCode: code) }
                case let .token(token, expiresIn): Task { await model.connect(withToken: token, expiresIn: expiresIn) }
                case let .failed(message): model.alert = message
                case nil: break
                }
            }
        }
    }
}

/// Gemini voiceover and background music
private struct VoiceoverSettings: View {
    @Environment(AppModel.self) private var model
    @State private var geminiKey = Keychain.get(Keychain.Key.geminiApiKey) ?? ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Add voiceover", isOn: $model.settings.voiceoverEnabled)
                Picker("Voice", selection: $model.settings.ttsVoice) {
                    ForEach(SettingsView.geminiVoices, id: \.self) { Text($0).tag($0) }
                }
                TextField("TTS model", text: $model.settings.ttsModel)
                SecureField("Gemini API key", text: $geminiKey)
                    .onChange(of: geminiKey) { _, v in Keychain.set(v.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.Key.geminiApiKey) }
            } header: {
                Text("Voiceover")
            } footer: {
                if geminiKey.isEmpty {
                    AudioService.envKey != nil
                         ? Text("The key field is empty; using GEMINI_API_KEY from the shell environment.")
                         : Text("No Gemini API key. Get one at aistudio.google.com and enter it here, or set the GEMINI_API_KEY environment variable.")
                } else {
                    Text("The key is stored in the Keychain. Audio is generated during rendering and isn't regenerated unless the text changes.")
                }
            }
            Section("Music") {
                Toggle("Background music (royalty-free beat)", isOn: $model.settings.musicEnabled)
            }
        }
    }
}

/// Claude Code model and Remotion video engine
private struct EngineSettings: View {
    @Environment(AppModel.self) private var model
    @State private var claudeStatus = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Model", selection: $model.settings.claudeModel) {
                    Text("Claude Code default").tag("")
                    Text("Opus 5.5").tag("claude-opus-5-5")
                    Text("Sonnet 5.5").tag("claude-sonnet-5-5")
                    Text("Haiku 5.5").tag("claude-haiku-5-5")
                }
                HStack {
                    Button("Check Claude Code") { checkClaude() }
                    Text(claudeStatus).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Analysis and text generation run in the background with the `claude` CLI on your Mac (using your own session).")
            }

            Section {
                LabeledContent("Status", value: RemotionService.isInstalled ? String(localized: "Installed") : String(localized: "Not installed"))
                if let job = model.setupJob {
                    HStack { ProgressView().controlSize(.small); Text(job.message).lineLimit(1) }
                } else {
                    Button(RemotionService.isInstalled ? String(localized: "Update Template") : String(localized: "Install Remotion")) { model.prepareRemotion() }
                }
                Button("Setup Checklist…") {
                    model.openStudio()
                    model.showSetup = true
                }
            } header: {
                Text("Remotion (Video Engine)")
            } footer: {
                Text("Requires Node.js. Template: \(Paths.remotion.path)")
            }
        }
    }

    private func checkClaude() {
        claudeStatus = String(localized: "Checking…")
        Task {
            do {
                let v = try await ProcessRunner.run("claude", ["--version"])
                claudeStatus = "✓ \(v.trimmingCharacters(in: .whitespacesAndNewlines))"
            } catch {
                claudeStatus = error.localizedDescription
            }
        }
    }
}

/// Shows the Instagram OAuth page and captures the code when the redirect URI is reached.
enum OAuthResult {
    case code(String)
    case token(String, expiresIn: Int?)
    case failed(String)
}

struct InstagramLoginSheet: View {
    let settings: AppSettings
    var onFinish: (OAuthResult?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                (settings.loginMode == .facebook ? Text("Facebook Login") : Text("Instagram Login")).font(.headline)
                Spacer()
                Button("Cancel") { onFinish(nil) }
            }
            .padding()
            if let url = InstagramAPI.authorizeURL(mode: settings.loginMode, appId: settings.metaAppId, redirectURI: settings.redirectURI, graphVersion: settings.graphVersion) {
                OAuthWebView(url: url, redirectURI: settings.redirectURI, onResult: onFinish)
            }
        }
        .frame(width: 520, height: 720)
    }
}

struct OAuthWebView: NSViewRepresentable {
    let url: URL
    let redirectURI: String
    var onResult: (OAuthResult?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: OAuthWebView
        init(_ parent: OAuthWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.absoluteString.hasPrefix(parent.redirectURI) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            // The code arrives in the query string, the token in the #fragment
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var params: [String: String] = [:]
            for item in comps?.queryItems ?? [] { params[item.name] = item.value }
            if let fragment = comps?.fragment {
                for item in URLComponents(string: "?" + fragment)?.queryItems ?? [] { params[item.name] = item.value }
            }
            if let token = params["access_token"] {
                parent.onResult(.token(token, expiresIn: params["expires_in"].flatMap(Int.init)))
            } else if let code = params["code"] {
                parent.onResult(.code(code))
            } else {
                parent.onResult(.failed(params["error_description"] ?? params["error_reason"] ?? String(localized: "Login couldn't be completed.")))
            }
        }
    }
}
