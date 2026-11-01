import AVKit
import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.glassCard(padding: 14)
    }
}

struct LocalImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}

/// Uses AppKit `AVPlayerView` because SwiftUI `VideoPlayer` crashes with a metadata error on macOS 27.
struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
    }
}

struct JobBanner: View {
    let job: JobState
    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "sparkles", size: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(job.message).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    RemainingTimeLabel(job: job)
                    if let p = job.progress {
                        Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ProgressBar(fraction: job.progress)
            }
            if let onCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel(Text("Cancel"))
            }
        }
        .glassCard(padding: 10)
    }
}

/// "About 3 min left" for a running job, refreshed every second; empty without an estimate.
struct RemainingTimeLabel: View {
    let job: JobState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let text = job.remainingText(now: context.date) {
                Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct ColorSwatch: View {
    let hex: String
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: hex))
            .frame(width: 28, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            .help(hex)
    }
}

struct StatusBadge: View {
    let status: PostStatus
    var body: some View {
        StatusPill(text: Text(status.label), color: status.color)
    }
}

extension PostStatus {
    var color: Color {
        switch self {
        case .published: .green
        case .scheduled: Brand.indigo
        case .ready: Brand.teal
        case .failed: .red
        case .rendering, .publishing: .orange
        case .draft: .gray
        }
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
