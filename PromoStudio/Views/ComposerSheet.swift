import SwiftUI

struct ComposerRequest: Identifiable {
    let id = UUID()
    let projectId: UUID
    let featureId: String?
    let suggestionId: String?
    /// Start from the user's own request (prompt)
    var custom = false
}

/// Pre-generation screen for picking a feature or custom request, theme, duration and notes.
struct ComposerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ComposerRequest
    var onCreated: (UUID) -> Void

    @State private var featureId: String = ""
    @State private var suggestionId: String = ""
    @State private var theme: VideoTheme = .hype
    @State private var seconds = 15
    @State private var notes = ""
    @State private var autoRender = true
    @State private var language = "tr"
    @State private var custom = false
    @State private var prompt = ""
    @State private var research = true
    /// For a custom request: a Claude-directed video (storyboard → code) or a quick template
    @State private var kind: CustomKind = .promo
    @State private var voiceover = true

    var body: some View {
        let analysis = model.project(request.projectId)?.analysis
        Form {
            Section {
                Picker("Source", selection: $custom) {
                    Text("Feature or Suggestion").tag(false)
                    Text("My Own Request").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: custom) { _, isCustom in autoRender = !isCustom }
                if custom {
                    TextField("Your request", text: $prompt, prompt: Text("e.g. We’re shipping a big update this weekend. Make an energetic promo film that highlights the new feature."), axis: .vertical)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .lineLimit(4...10)
                    Picker("Video type", selection: $kind) {
                        Text("Promo film (directed by Claude)").tag(CustomKind.promo)
                        Text("Free-form video (directed by Claude)").tag(CustomKind.freeform)
                        Text("Quick template (screenshots)").tag(CustomKind.template)
                    }
                    Toggle("Let Claude research the web", isOn: $research)
                    if kind != .freeform {
                        Picker("Feature to highlight", selection: $featureId) {
                            Text("Let Claude choose").tag("")
                            ForEach(analysis?.features ?? []) { f in Text("\(f.emoji) \(f.name)").tag(f.id) }
                        }
                    }
                } else {
                    Picker("Feature", selection: $featureId) {
                        Text("General overview").tag("")
                        ForEach(analysis?.features ?? []) { f in Text("\(f.emoji) \(f.name)").tag(f.id) }
                    }
                    Picker("Content idea", selection: $suggestionId) {
                        Text("Let Claude choose").tag("")
                        ForEach(analysis?.suggestions ?? []) { s in Text(s.title).tag(s.id) }
                    }
                    TextField("Extra notes (e.g. new version highlight, 20% off)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            } header: {
                Text("What should it be about?")
            } footer: {
                if custom && kind == .freeform {
                    Text("Claude makes exactly the video you describe (a news report, a story, an explainer…) without advertising the app. The app’s features, screenshots or a download call appear only if your request asks for them. You approve the storyboard first, as with a promo film.")
                } else if custom && directed {
                    Text("Claude first writes a scene-by-scene storyboard: visuals, on-screen text, voiceover and effects. You revise and approve the storyboard; then Claude codes the video, checks its frames and renders it. You can request revisions on the video too.")
                } else if custom {
                    Text("Claude combines your request with the app’s features, brand colors and screenshots. With research on, it verifies current facts on the web and shows its sources. After you see the script, you can have Claude revise it in the studio.")
                }
            }
            Section("Video") {
                Picker("Language", selection: $language) {
                    ForEach(ContentLanguage.all) { Text($0.label).tag($0.id) }
                }
                if custom && directed {
                    Stepper("Duration: \(seconds) s", value: $seconds, in: 10...60, step: 1)
                    Toggle("Voiceover", isOn: $voiceover)
                } else {
                    Picker("Theme", selection: $theme) {
                        ForEach(VideoTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Duration: \(seconds) s", value: $seconds, in: 8...45, step: 1)
                    Toggle("Render automatically when the script is ready", isOn: $autoRender)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    let feature = custom && kind == .freeform ? nil : analysis?.features.first { $0.id == featureId }
                    let suggestion = custom ? nil : analysis?.suggestions.first { $0.id == suggestionId }
                    let brief = custom ? PostBrief(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), research: research) : nil
                    if custom, directed, let brief {
                        if let id = model.createDirectedPost(projectId: request.projectId, feature: feature, seconds: seconds, language: language, brief: brief, voiceover: voiceover, style: kind == .freeform ? .freeform : .promo) {
                            dismiss()
                            onCreated(id)
                        }
                    } else if let id = model.createPost(projectId: request.projectId, feature: feature, suggestion: suggestion, theme: theme, seconds: seconds, notes: custom ? "" : notes, autoRender: autoRender, language: language, brief: brief) {
                        dismiss()
                        onCreated(id)
                    }
                } label: {
                    createButtonTitle
                }
                .disabled(custom && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            language = model.settings.contentLanguage
            custom = request.custom
            autoRender = !request.custom
            voiceover = model.settings.voiceoverEnabled
            if request.custom { seconds = 20 }
            featureId = request.featureId ?? ""
            suggestionId = request.suggestionId ?? ""
            theme = analysis?.suggestions.first { $0.id == request.suggestionId }?.theme ?? model.settings.defaultTheme
        }
    }

    private enum CustomKind { case promo, freeform, template }

    /// Claude writes a storyboard and codes the video (promo film or free-form video)
    private var directed: Bool { kind != .template }

    private var createButtonTitle: Text {
        if custom && directed {
            research ? Text("Research and Write Storyboard") : Text("Write Storyboard")
        } else if custom && research {
            Text("Research and Write Script")
        } else {
            Text("Create Script")
        }
    }
}
