import SwiftUI

/// Captures screens from the simulator in every language: recipe, language selection and capture.
struct LocalScreensSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID

    @State private var languages: Set<String> = ["en"]

    var body: some View {
        let project = model.project(projectId)
        let recipe = project?.captureRecipe
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Localized Screens from Simulator").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            if let job = model.jobs[projectId] {
                JobBanner(job: job) { model.cancel(projectId) }.padding(.horizontal)
            }
            Form {
                if let recipe, let project {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                            ForEach(ContentLanguage.all) { lang in
                                Toggle(lang.label, isOn: Binding(
                                    get: { languages.contains(lang.id) },
                                    set: { on in if on { languages.insert(lang.id) } else { languages.remove(lang.id) } }
                                ))
                            }
                        }
                        HStack {
                            Button("Re-extract Recipe") { model.createCaptureRecipe(projectId) }
                            Spacer()
                            Button("Capture Screens") { model.captureLocalizedScreens(projectId, languages: Array(languages).sorted()) }
                                .buttonStyle(.borderedProminent)
                                .disabled(languages.isEmpty || recipe.shots.isEmpty)
                        }
                        .disabled(model.jobs[projectId] != nil)
                    } header: {
                        Text("Languages")
                    } footer: {
                        Text("On the first capture, the app is built for the Simulator (this may take a few minutes). Captured screens are added as that language's version of the matching image and are used automatically when videos are adapted to another language.")
                    }
                    Section("Screens to Capture") {
                        ForEach(recipe.shots) { shot in
                            HStack(spacing: 12) {
                                LocalImage(url: Paths.projectAssets(projectId).appendingPathComponent(shot.assetFile), contentMode: .fit)
                                    .frame(width: 30, height: 54)
                                VStack(alignment: .leading) {
                                    Text(shot.label)
                                    Text([shot.url, shot.extraArguments.joined(separator: " "), (shot.taps ?? []).map { String(localized: "tap: \($0)") }.joined(separator: " → ")].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(variants(of: shot.assetFile, in: project)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        DisclosureGroup("Recipe Details") {
                            LabeledContent("App", value: recipe.bundleId)
                            LabeledContent("Build", value: "\(recipe.projectFile) · \(recipe.scheme)")
                            LabeledContent("Launch arguments", value: recipe.launchArguments.joined(separator: " "))
                            if !recipe.notes.isEmpty {
                                Text(recipe.notes).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Claude Code examines the app's code to find which demo arguments and deep links open the raw screens. Promo Studio then captures those screens from the iOS Simulator in each language.")
                        Text("Screens to localize: \(project.map { model.localizableScreens($0).count } ?? 0)")
                            .foregroundStyle(.secondary)
                        Button("Extract Recipe") { model.createCaptureRecipe(projectId) }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.jobs[projectId] != nil)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 640, height: 640)
    }

    private func variants(of file: String, in project: AppProject) -> String {
        project.assets.filter { $0.variantOf == file }.compactMap(\.language).sorted().map { $0.uppercased() }.joined(separator: " ")
    }
}
