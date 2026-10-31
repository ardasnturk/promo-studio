import SwiftUI

/// Menu bar window (same layout as Remote Code's menu): gradient header with status and counters,
/// then only what matters right now: setup, pending approvals, in-progress renders, upcoming posts
/// and a quick new video. Details live in the studio window.
struct MenuPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    /// Measured height of the scrolling sections: the menu window sizes to its ideal size,
    /// and a bare ScrollView has no ideal height, so an explicit one is needed.
    @State private var contentHeight: CGFloat = 0
    @State private var prompt = ""
    @State private var projectId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.isSetupIncomplete { setupWarning }
                    updateBanner
                    attention
                    production
                    upcoming
                    quickCreate
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 520))
            footer
        }
        .frame(width: 360)
        .background(BrandBackground(intensity: 0.8))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("MenuBarIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Promo Studio").font(.title3.weight(.bold))
                    Text("\(model.data.projects.count) projects · \(model.data.accounts.count) Instagram accounts")
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: statusText, color: statusColor, onGradient: true)
            }
            HStack(alignment: .top, spacing: 8) {
                stat(Text(verbatim: "\(productionJobs.count)"), symbol: "sparkles", label: Text("in production"))
                stat(Text(verbatim: "\(scheduled.count)"), symbol: "calendar", label: Text("scheduled"))
                stat(Text(weeklyViews.formatted(.number.notation(.compactName))), symbol: "eye.fill", label: Text("views this week"))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Brand.gradient)
    }

    private func stat(_ value: Text, symbol: String, label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                value.font(.headline.monospacedDigit())
            } icon: {
                Image(systemName: symbol).font(.caption)
            }
            label.font(.caption2).opacity(0.85).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statusText: Text {
        if model.isSetupIncomplete || !failed.isEmpty { return Text("Needs attention") }
        return productionJobs.isEmpty ? Text("Ready") : Text("Working")
    }

    private var statusColor: Color {
        if model.isSetupIncomplete || !failed.isEmpty { return .red }
        return productionJobs.isEmpty ? .green : .orange
    }

    // MARK: Sections

    private var setupWarning: some View {
        Button {
            model.openStudio()
            model.showSetup = true
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: "exclamationmark.triangle.fill", colors: [.orange, .red], size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup isn't finished").font(.callout.weight(.semibold))
                    Text("Click to see what's missing.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var updateBanner: some View {
        if let release = model.updater.availableRelease {
            Button {
                SettingsWindow.show(using: openSettings)
            } label: {
                HStack(spacing: 10) {
                    IconBadge(symbol: "arrow.down.circle.fill", colors: [.green, Brand.teal], size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Promo Studio \(release.version.description) Is Available").font(.callout.weight(.semibold))
                        Text("Install it in Settings → Updates.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }

    /// Posts awaiting storyboard approval and failed posts
    @ViewBuilder private var attention: some View {
        let approvals = awaitingApproval
        if !approvals.isEmpty || !failed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Waiting for you")
                ForEach(approvals) { post in
                    postButton(post, symbol: "film.stack", colors: [Brand.violet, Brand.pink],
                               detail: Text("Storyboard ready for approval"))
                }
                ForEach(failed) { post in
                    postButton(post, symbol: "exclamationmark.triangle.fill", colors: [.orange, .red],
                               detail: Text(post.lastError ?? String(localized: "Failed")))
                }
            }
            .glassCard()
        }
    }

    private func postButton(_ post: ContentPost, symbol: String, colors: [Color], detail: Text) -> some View {
        Button {
            open(post.id)
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, colors: colors, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.title).font(.callout.weight(.semibold)).lineLimit(1)
                    detail.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var production: some View {
        let jobs = productionJobs
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("In production")
                ForEach(jobs, id: \.id) { item in
                    HStack(spacing: 10) {
                        thumbnail(item.post)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(item.job.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            ProgressBar(fraction: item.job.progress)
                        }
                        Button {
                            model.cancel(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                        .accessibilityLabel(Text("Cancel"))
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if item.post != nil { open(item.id) } }
                }
            }
            .glassCard()
        }
    }

    @ViewBuilder private var upcoming: some View {
        let next = Array(scheduled.prefix(3))
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Up next")
                ForEach(next) { post in
                    Button {
                        open(post.id)
                    } label: {
                        HStack(spacing: 10) {
                            thumbnail(post)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.title).font(.callout).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text(post.scheduledAt?.formatted(.relative(presentation: .named)) ?? "")
                                    if let account = model.project(post.projectId).flatMap({ model.account(for: $0) }) {
                                        Text(verbatim: "· @\(account.username)")
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassCard()
        }
    }

    /// Pick a project and write the request: Claude writes the storyboard, approval happens in the studio or this panel.
    @ViewBuilder private var quickCreate: some View {
        let projects = model.data.projects.filter { $0.analysis != nil }
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("New promo film")
            if projects.isEmpty {
                Text("Add and analyze a project in the studio first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Project", selection: Binding(get: { projectId ?? projects.first?.id }, set: { projectId = $0 })) {
                    ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                TextField("What should the video be about?", text: $prompt, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    create(projectId ?? projects.first?.id)
                } label: {
                    Label("Write Storyboard", systemImage: "sparkles")
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button {
                model.openStudio()
            } label: {
                Label("Open Studio", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .glassCard()
    }

    private var footer: some View {
        HStack {
            Button {
                SettingsWindow.show(using: openSettings)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            Spacer()
            Text(verbatim: "Promo Studio \(model.updater.currentVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: Data

    private struct ProductionItem {
        let id: UUID
        let job: JobState
        let post: ContentPost?
        let title: String
    }

    /// Post and project jobs (excludes Promo Templates setup and library jobs)
    private var productionJobs: [ProductionItem] {
        model.jobs.compactMap { id, job -> ProductionItem? in
            if let post = model.post(id) { return ProductionItem(id: id, job: job, post: post, title: post.title) }
            if let project = model.project(id) { return ProductionItem(id: id, job: job, post: nil, title: project.name) }
            return nil
        }
        .sorted { $0.title < $1.title }
    }

    private var awaitingApproval: [ContentPost] {
        model.data.posts.filter { post in
            guard let directed = post.directed else { return false }
            return !directed.produced && !directed.storyboard.scenes.isEmpty && model.jobs[post.id] == nil
        }
    }

    private var failed: [ContentPost] {
        model.data.posts.filter { $0.status == .failed }
    }

    private var scheduled: [ContentPost] {
        model.data.posts
            .filter { $0.status == .scheduled }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
    }

    private var weeklyViews: Int {
        let since = Date.now.addingTimeInterval(-7 * 86400)
        return model.data.posts
            .filter { ($0.publishedAt ?? .distantPast) >= since }
            .reduce(0) { $0 + ($1.metrics?.views ?? 0) }
    }

    private func thumbnail(_ post: ContentPost?) -> some View {
        LocalImage(url: post.flatMap { model.coverURL($0) })
            .frame(width: 24, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func open(_ postId: UUID) {
        model.requestedPost = postId
        model.openStudio()
    }

    private func create(_ projectId: UUID?) {
        guard let projectId else { return }
        let brief = PostBrief(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), research: true)
        if model.createDirectedPost(projectId: projectId, feature: nil, seconds: 20, language: nil, brief: brief, voiceover: model.settings.voiceoverEnabled) != nil {
            prompt = ""
        }
    }
}
