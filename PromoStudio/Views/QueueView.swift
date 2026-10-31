import SwiftUI

/// Publishing calendar of content across all projects, grouped by status.
struct QueueView: View {
    @Environment(AppModel.self) private var model
    @State private var openPost: UUID?

    var body: some View {
        let posts = model.data.posts
        let scheduled = posts.filter { $0.status == .scheduled }.sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
        let inProgress = posts.filter { [.draft, .rendering, .ready, .publishing, .failed].contains($0.status) }.sorted { $0.createdAt > $1.createdAt }
        let published = posts.filter { $0.status == .published }.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if posts.isEmpty {
                    ContentUnavailableView(
                        "No Content Yet",
                        systemImage: "sparkles.tv",
                        description: Text("Add a project folder from the sidebar; Promo Studio will analyze it and suggest content.")
                    )
                    .padding(.top, 80)
                }
                group("Scheduled", scheduled, byDay: true)
                group("In Progress", inProgress)
                group("Published", published)
            }
            .padding(24)
        }
        .brandWindowBackground()
        .navigationTitle("Publishing Calendar")
        .sheet(item: Binding(get: { openPost.map(PostRef.init) }, set: { openPost = $0?.id })) { ref in
            PostEditorView(postId: ref.id) { newId in openPost = newId }
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ posts: [ContentPost], byDay: Bool = false) -> some View {
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title2.weight(.bold))
                if byDay {
                    let days = Dictionary(grouping: posts) { Calendar.current.startOfDay(for: $0.scheduledAt ?? .now) }
                    ForEach(days.keys.sorted(), id: \.self) { day in
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.headline).foregroundStyle(.secondary)
                        ForEach(days[day] ?? []) { row($0) }
                    }
                } else {
                    ForEach(posts) { row($0) }
                }
            }
        }
    }

    private func row(_ post: ContentPost) -> some View {
        Button { openPost = post.id } label: {
            PostRow(post: post, projectName: model.project(post.projectId)?.name)
        }
        .buttonStyle(.plain)
    }
}
