import SwiftUI

struct AnalyticsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedAccount: String?

    var body: some View {
        let accountId = selectedAccount ?? model.data.accounts.first?.userId
        let published = model.data.posts.filter { post in
            post.status == .published && (post.accountId ?? model.project(post.projectId)?.accountId) == accountId
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.data.accounts.count > 1 {
                    Picker("Account", selection: Binding(get: { accountId }, set: { selectedAccount = $0 })) {
                        ForEach(model.data.accounts) { Text("@\($0.username)").tag(Optional($0.userId)) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)
                }
                if let a = model.account(accountId) {
                    Card {
                        HStack(spacing: 16) {
                            AsyncImage(url: a.profilePictureURL.flatMap(URL.init(string:))) { img in
                                img.resizable()
                            } placeholder: { Circle().fill(.quaternary) }
                                .frame(width: 64, height: 64).clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text("@\(a.username)").font(.title2.bold())
                                if let n = a.name { Text(n).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            stat("Followers", a.followers)
                            stat("Posts", a.mediaCount)
                        }
                    }
                } else {
                    Text("Connect your Instagram account to see statistics.").foregroundStyle(.secondary)
                }

                let sum = { (kp: KeyPath<PostMetrics, Int?>) in published.compactMap { $0.metrics?[keyPath: kp] }.reduce(0, +) }
                HStack(spacing: 12) {
                    Card { stat("Total views", sum(\.views)) }
                    Card { stat("Total reach", sum(\.reach)) }
                    Card { stat("Likes", sum(\.likes)) }
                    Card { stat("Saves", sum(\.saved)) }
                    Card { stat("Shares", sum(\.shares)) }
                }

                Text("Published Content").font(.title2.bold())
                Table(published.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }) {
                    TableColumn("Title") { Text($0.title) }
                    TableColumn("Project") { Text(model.project($0.projectId)?.name ?? "–") }
                    TableColumn("Date") { Text($0.publishedAt?.formatted(date: .abbreviated, time: .shortened) ?? "–") }
                    TableColumn("Views") { Text(num($0.metrics?.views)) }
                    TableColumn("Reach") { Text(num($0.metrics?.reach)) }
                    TableColumn("Likes") { Text(num($0.metrics?.likes)) }
                    TableColumn("Comments") { Text(num($0.metrics?.comments)) }
                    TableColumn("Saves") { Text(num($0.metrics?.saved)) }
                }
                .frame(minHeight: 300)
            }
            .padding(24)
        }
        .brandWindowBackground()
        .navigationTitle("Analytics")
        .toolbar {
            Button {
                model.refreshMetrics()
                Task { await model.refreshAccounts() }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(!model.isConnected)
        }
    }

    private func num(_ v: Int?) -> String { v.map { $0.formatted() } ?? "–" }

    private func stat(_ title: LocalizedStringKey, _ value: Int?) -> some View {
        VStack(alignment: .leading) {
            Text(num(value)).font(.title.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
