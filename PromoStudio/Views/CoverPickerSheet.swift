import AVFoundation
import SwiftUI

/// Picks the cover frame from the rendered video. Instagram gets the same moment as the Reel's cover.
struct CoverPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let post: ContentPost
    let videoURL: URL

    @State private var duration: Double = 0
    @State private var sec: Double = 0
    @State private var frame: NSImage?
    @State private var saving = false
    @State private var generator: AVAssetImageGenerator?

    var body: some View {
        VStack(spacing: 14) {
            Text("Choose Cover").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.black)
                if let frame {
                    Image(nsImage: frame).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 270, height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Slider(value: $sec, in: 0...max(duration, 0.1))
                .disabled(duration == 0)
            Text(verbatim: String(format: "%.1f s", sec)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("This frame is used as the cover here and on Instagram.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    saving = true
                    Task {
                        await model.setCover(post.id, at: sec)
                        dismiss()
                    }
                } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text("Use as Cover") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(duration == 0 || saving)
            }
        }
        .padding(20)
        .frame(width: 330)
        .task {
            let asset = AVURLAsset(url: videoURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.maximumSize = CGSize(width: 540, height: 960)
            generator = gen
            duration = (try? await asset.load(.duration).seconds) ?? 0
            sec = min(post.coverSec ?? LibraryService.coverSec, duration)
            await loadFrame()
        }
        .task(id: sec) { await loadFrame() }
    }

    private func loadFrame() async {
        guard let generator else { return }
        let time = CMTime(seconds: sec, preferredTimescale: 600)
        if let image = try? await generator.image(at: time).image {
            frame = NSImage(cgImage: image, size: .zero)
        }
    }
}
