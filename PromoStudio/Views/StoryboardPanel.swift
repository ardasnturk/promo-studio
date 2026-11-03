import SwiftUI

/// Storyboard of a Claude-directed video: concept, scene cards and production notes. Fields are also editable by hand.
struct StoryboardPanel: View {
    @Environment(AppModel.self) private var model
    let postId: UUID
    let project: AppProject

    var body: some View {
        if let post = model.post(postId), let directed = post.directed {
            let busy = model.jobs[postId] != nil
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if directed.storyboard.scenes.isEmpty {
                        (busy ? Text("Claude is writing the storyboard…") : Text("No storyboard.")).foregroundStyle(.secondary)
                    } else {
                        GroupBox("Concept") {
                            TextField("Concept", text: binding(\.concept), axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(2...8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let people = directed.storyboard.people, !people.isEmpty {
                            PeoplePhotosBox(post: post, people: people, busy: busy)
                        }
                        ForEach(Array(directed.storyboard.scenes.enumerated()), id: \.element.id) { index, scene in
                            sceneCard(index: index, scene: scene, durationOverride: post.spec.scenes.indices.contains(index) && directed.produced ? post.spec.scenes[index].durationSec : nil)
                        }
                        if directed.produced {
                            if let summary = directed.summary {
                                GroupBox("Claude’s Notes") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(summary).font(.callout)
                                        if let notes = directed.notes, !notes.isEmpty {
                                            Text(notes).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                }
                            }
                            HStack {
                                Button {
                                    model.produce(postId)
                                } label: { Label("Recode Video from Storyboard", systemImage: "arrow.triangle.2.circlepath") }
                                    .disabled(busy)
                                Spacer()
                            }
                            Text("Changes you make to the storyboard by hand aren’t applied to the video automatically. Give instructions in the “Revise with Claude” tab, or recode the video from scratch.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("You can fix the text by hand or give instructions in the “Revise with Claude” tab. When it’s ready, click “Approve and Produce Video” on the left.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
    }

    private func sceneCard(index: Int, scene: StoryScene, durationOverride: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scene \(index + 1)").font(.headline)
                Text("\(durationOverride ?? scene.durationSec, specifier: "%.1f") s")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if let sfx = scene.sfx {
                    Label(sfx, systemImage: "speaker.wave.2").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            labeled("On-screen text", sceneBinding(index, \.text), lines: 1...3, font: .body.weight(.semibold))
            labeled("Visuals and motion", sceneBinding(index, \.visual), lines: 2...8, font: .callout)
            if scene.voiceover != nil {
                labeled("Voiceover", optionalSceneBinding(index, \.voiceover), lines: 1...4, font: .callout.italic())
            }
            if let assets = scene.assets, !assets.isEmpty {
                HStack(spacing: 8) {
                    ForEach(assets, id: \.self) { file in
                        LocalImage(url: Paths.projectAssets(project.id).appendingPathComponent(file))
                            .frame(width: 44, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .help(file)
                    }
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func labeled(_ title: LocalizedStringKey, _ text: Binding<String>, lines: ClosedRange<Int>, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            TextField(title, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .lineLimit(lines)
        }
    }

    private func binding(_ kp: WritableKeyPath<Storyboard, String>) -> Binding<String> {
        Binding(
            get: { model.post(postId)?.directed?.storyboard[keyPath: kp] ?? "" },
            set: { v in model.updatePost(postId) { $0.directed?.storyboard[keyPath: kp] = v } }
        )
    }

    private func sceneBinding(_ index: Int, _ kp: WritableKeyPath<StoryScene, String>) -> Binding<String> {
        Binding(
            get: {
                guard let scenes = model.post(postId)?.directed?.storyboard.scenes, scenes.indices.contains(index) else { return "" }
                return scenes[index][keyPath: kp]
            },
            set: { v in
                model.updatePost(postId) { p in
                    guard p.directed?.storyboard.scenes.indices.contains(index) == true else { return }
                    p.directed?.storyboard.scenes[index][keyPath: kp] = v
                }
            }
        )
    }

    private func optionalSceneBinding(_ index: Int, _ kp: WritableKeyPath<StoryScene, String?>) -> Binding<String> {
        Binding(
            get: {
                guard let scenes = model.post(postId)?.directed?.storyboard.scenes, scenes.indices.contains(index) else { return "" }
                return scenes[index][keyPath: kp] ?? ""
            },
            set: { v in
                model.updatePost(postId) { p in
                    guard p.directed?.storyboard.scenes.indices.contains(index) == true else { return }
                    p.directed?.storyboard.scenes[index][keyPath: kp] = v
                }
            }
        )
    }
}

/// The real people of the storyboard: the downloaded photo and Codex's edit side by side, to pick one or edit again.
struct PeoplePhotosBox: View {
    @Environment(AppModel.self) private var model
    let post: ContentPost
    let people: [StoryPerson]
    let busy: Bool
    @State private var instructions: [String: String] = [:]

    var body: some View {
        GroupBox("People") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(people, id: \.name) { person in
                    row(person)
                    if person.name != people.last?.name { Divider() }
                }
                if model.usesEditedPhotos(post) {
                    Label("Photos edited with AI: label the post as AI-made on Instagram, and don’t present the edit as a real moment.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ person: StoryPerson) -> some View {
        let photos = StudioService.personPhotos(post, person)
        let dir = Paths.post(post.id)
        let usingEdit = person.useOriginal != true && photos.edited != nil
        return VStack(alignment: .leading, spacing: 8) {
            Text(person.name).font(.headline)
            HStack(alignment: .top, spacing: 10) {
                thumbnail(photos.original.map { dir.appendingPathComponent($0.photo) }, label: "Original", selected: !usingEdit && photos.original != nil) {
                    model.setUseOriginalPhoto(true, name: person.name, postId: post.id)
                }
                if model.settings.editPhotosWithCodex || photos.edited != nil {
                    thumbnail(photos.edited.map { dir.appendingPathComponent($0.photo) }, label: "Edited", selected: usingEdit) {
                        model.setUseOriginalPhoto(false, name: person.name, postId: post.id)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if photos.original == nil {
                        Text(busy ? "Looking for a photo…" : "No photo found; the video shows the name instead.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = person.editError {
                        Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if photos.original != nil, CodexImage.isInstalled {
                        TextField("How Codex should change the photo", text: Binding(
                            get: { instructions[person.name] ?? person.edit ?? "" },
                            set: { instructions[person.name] = $0 }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        .font(.caption)
                        Button(photos.edited == nil ? "Edit with Codex" : "Edit Again") {
                            model.editPersonPhoto(name: person.name, postId: post.id, instruction: instructions[person.name])
                        }
                        .controlSize(.small)
                        .disabled(busy || (instructions[person.name] ?? person.edit ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func thumbnail(_ url: URL?, label: LocalizedStringKey, selected: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                LocalImage(url: url, contentMode: .fill)
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                Text(label).font(.caption2).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(url == nil || busy)
    }
}
