import Foundation

/// Compares today's emotion event counts against a rolling baseline.
/// Uses Z-score per label. Requires at least 3 past days before flagging.
struct OutlierDetector {
    let threshold: Double
    let minBaselineDays: Int

    init(threshold: Double = 2.0, minBaselineDays: Int = 3) {
        self.threshold = threshold
        self.minBaselineDays = minBaselineDays
    }

    struct DetectionResult {
        var flags: [String: String]   // label -> "normal" | "elevated (+Xσ)" | "low (-Xσ)"
        var moodSummary: String
    }

    func analyze(today: DayRecord, history: [DayRecord]) -> DetectionResult {
        guard history.count >= minBaselineDays else {
            return DetectionResult(
                flags: [:],
                moodSummary: "Collecting baseline (\(history.count)/\(minBaselineDays) days)..."
            )
        }

        // All labels seen across history
        let allLabels = Set(history.flatMap { $0.counts.keys })

        var flags: [String: String] = [:]
        for label in allLabels {
            let historicalVals = history.map { Double($0.counts[label] ?? 0) }
            let todayVal = Double(today.counts[label] ?? 0)
            flags[label] = zFlag(todayVal: todayVal, historicalVals: historicalVals)
        }

        return DetectionResult(flags: flags, moodSummary: deriveMood(flags: flags))
    }

    private func zFlag(todayVal: Double, historicalVals: [Double]) -> String {
        let mean = historicalVals.reduce(0, +) / Double(historicalVals.count)
        let variance = historicalVals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(historicalVals.count)
        let std = variance.squareRoot()
        guard std > 0.5 else { return "normal" }
        let z = (todayVal - mean) / std
        if z >  threshold { return String(format: "elevated (+%.1fσ)", z) }
        if z < -threshold { return String(format: "low (%.1fσ)", abs(z)) }
        return "normal"
    }

    private func deriveMood(flags: [String: String]) -> String {
        let elevated = flags.filter { $0.value.contains("elevated") }.keys

        // High arousal + negative valence = distress signals
        let distressSignals = elevated.filter {
            $0.contains("High") && $0.contains("Negative")
        }.count

        // High arousal + positive valence = excitement
        let excitedSignals = elevated.filter {
            $0.contains("High") && $0.contains("Positive")
        }.count

        // Low arousal + negative = anxious/sad
        let anxiousSignals = elevated.filter {
            $0.contains("Low") && $0.contains("Negative")
        }.count

        if distressSignals > 0 { return "Distressed" }
        if anxiousSignals > 0  { return "Anxious" }
        if excitedSignals > 0  { return "Excited / Playful" }
        if elevated.isEmpty    { return "Normal" }
        return "Unusual activity"
    }
}
