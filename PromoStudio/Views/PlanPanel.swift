import SwiftUI

/// Says how far a planned post goes on its own.
struct PlanFootnote: View {
    let needsAccount: Bool
    let autoPublish: Bool
    let autoApprove: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if autoApprove, autoPublish {
                Text("It runs from start to finish and posts without asking you.")
            } else if autoPublish {
                Text("It waits for your approval of the storyboard, then posts when it’s ready.")
            } else if autoApprove {
                Text("It’s made without asking you, then waits for you to post it.")
            } else {
                Text("It stops at the storyboard and waits for your approval.")
            }
            if needsAccount {
                Text("To post automatically, choose an Instagram account or a project with one.")
            }
            Text("Promo Studio has to be open and the Mac awake at that time; otherwise it starts when they are. If that’s over an hour late, it isn’t posted automatically.")
        }
    }
}

/// A planned post before its time: the request and its options can still change.
struct PlanPanel: View {
    @Environment(AppModel.self) private var model
    let postId: UUID
    @State private var request = ""

    var body: some View {
        if let post = model.post(postId), let plan = post.plan {
            let hasAccount = model.hasDestination(post)
            Form {
                Section("Request") {
                    TextField("Request", text: $request, axis: .vertical)
                        .labelsHidden()
                        .lineLimit(4...10)
                        .onChange(of: request) { model.updatePlan(postId, request: request) }
                }
                Section("Plan") {
                    DatePicker("Start at", selection: Binding(get: { plan.runAt }, set: { model.updatePlan(postId, runAt: $0) }), in: Date()...)
                    if post.external == nil {
                        Toggle(post.isImage ? "Approve the design automatically" : "Approve the storyboard automatically", isOn: Binding(get: { plan.autoApprove }, set: { model.updatePlan(postId, autoApprove: $0) }))
                    }
                    Toggle("Post automatically when it’s ready", isOn: Binding(get: { plan.autoPublish && hasAccount }, set: { model.updatePlan(postId, autoPublish: $0) }))
                        .disabled(!hasAccount)
                    if plan.autoPublish, hasAccount, post.canPostToFeed {
                        Picker("Share as", selection: Binding(get: { post.isStory }, set: { model.setPlacement($0 ? .story : .feed, forPost: postId) })) {
                            (post.isImage ? ((post.directed?.slides ?? 1) > 1 ? Text("Carousel") : Text("Post")) : Text("Reel")).tag(false)
                            Text("Story").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    PlanFootnote(needsAccount: !hasAccount, autoPublish: plan.autoPublish, autoApprove: plan.autoApprove || post.external != nil)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button { model.startPlan(postId) } label: { Label("Start Now", systemImage: "play.fill") }
                        .disabled(model.jobs[postId] != nil)
                }
            }
            .formStyle(.grouped)
            .onAppear { request = post.brief?.prompt ?? post.external?.request ?? "" }
        }
    }
}

/// On a started plan: what it will still do by itself.
struct PlanStatusLine: View {
    let plan: CreationPlan

    var body: some View {
        if plan.startedLate == true {
            Label("It started over an hour late, so it wasn’t posted automatically. Check it and post it yourself.", systemImage: "clock.badge.exclamationmark")
                .font(.caption).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if plan.autoApprove || plan.autoPublish {
            Label(plan.autoPublish ? "Planned: it posts automatically when it’s ready." : "Planned: the storyboard is approved automatically.", systemImage: "calendar.badge.clock")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
