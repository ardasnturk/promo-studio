import Foundation

/// How long recent jobs of each kind took, for the remaining-time estimate. Kept in
/// `timings.json` next to the data; only successful jobs are recorded.
@MainActor
final class JobTimings {
    static let shared = JobTimings()
    /// Durations kept per kind
    static let keep = 10
    /// Estimates start after this many finished jobs of a kind
    static let minimumSamples = 2

    private let url = Paths.root.appendingPathComponent("timings.json")
    private var durations: [String: [TimeInterval]]

    private init() {
        durations = (try? JSONDecoder().decode([String: [TimeInterval]].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// Median of the recent durations, or nil while there are too few.
    func typicalDuration(of kind: JobKind) -> TimeInterval? {
        guard kind != .other, let values = durations[kind.rawValue], values.count >= Self.minimumSamples else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    func record(_ kind: JobKind, duration: TimeInterval) {
        guard kind != .other, duration > 1 else { return }
        var values = durations[kind.rawValue] ?? []
        values.append(duration)
        durations[kind.rawValue] = Array(values.suffix(Self.keep))
        if let data = try? JSONEncoder().encode(durations) { try? data.write(to: url, options: .atomic) }
    }
}

extension JobState {
    /// "About 3 min left", "About 40 s left", "Almost done…"; nil without an estimate.
    func remainingText(now: Date = .now) -> String? {
        guard let estimatedEnd else { return nil }
        let seconds = estimatedEnd.timeIntervalSince(now)
        if seconds < 5 { return String(localized: "Almost done…") }
        if seconds < 60 {
            let rounded = max(5, Int((seconds / 5).rounded()) * 5)
            return String(localized: "About \(rounded) s left")
        }
        let minutes = Int((seconds / 60).rounded())
        return String(localized: "About \(minutes) min left")
    }
}
