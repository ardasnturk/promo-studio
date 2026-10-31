import SwiftUI

/// Setup checklist: required tools (Claude Code, Node.js, Remotion) and optional ones.
struct SetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onOpenSettings: () -> Void
    var onInstallTemplates: () -> Void
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checklist").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Up Promo Studio").font(.title2.bold())
                    Text("Promo Studio uses tools installed on this Mac.").foregroundStyle(.secondary)
                }
            }
            if let requirements = model.requirements {
                let required = requirements.filter(\.isRequired)
                let optional = requirements.filter { !$0.isRequired }
                section("Required", required)
                section("Optional", optional)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…") }
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            if let job = model.setupJob {
                JobBanner(job: job)
            }
            HStack {
                Link("Setup Guide", destination: URL(string: "https://github.com/ardasnturk/promo-studio/blob/main/docs/SETUP.md")!)
                    .font(.callout)
                Spacer()
                Button {
                    Task {
                        checking = true
                        await model.refreshRequirements()
                        checking = false
                    }
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check Again") }
                }
                .disabled(checking)
                Button(model.isSetupIncomplete ? "Later" : "Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .task { await model.refreshRequirements() }
    }

    private func section(_ title: LocalizedStringKey, _ items: [Requirement]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(items) { requirement in
                    row(requirement)
                    if requirement.id != items.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func row(_ requirement: Requirement) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(requirement)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(requirement.item)).fontWeight(.medium)
                Text(requirement.detail)
                    .font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if requirement.status != .ready { action(requirement) }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusIcon(_ requirement: Requirement) -> some View {
        switch requirement.status {
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .missing: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notSetUp: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func title(_ item: Requirement.Item) -> LocalizedStringKey {
        switch item {
        case .claude: "Claude Code"
        case .node: "Node.js"
        case .remotion: "Remotion (Video Engine)"
        case .git: "git"
        case .xcode: "Xcode"
        case .gemini: "Gemini API Key"
        case .instagram: "Instagram"
        case .templates: "Promo Templates"
        }
    }

    @ViewBuilder
    private func action(_ requirement: Requirement) -> some View {
        switch requirement.item {
        case .claude:
            Link("Get Claude Code", destination: URL(string: "https://claude.com/claude-code")!)
        case .node:
            Link("nodejs.org", destination: URL(string: "https://nodejs.org")!)
        case .remotion:
            Button("Install") { model.prepareRemotion() }
                .disabled(model.setupJob != nil || model.requirements?.first { $0.item == .node }?.status != .ready)
        case .gemini, .instagram:
            Button("Open Settings") {
                dismiss()
                onOpenSettings()
            }
        case .templates:
            Button("Install…") {
                dismiss()
                onInstallTemplates()
            }
        case .git, .xcode:
            EmptyView()
        }
    }
}
