import SwiftUI

struct ContentView: View {
    @StateObject private var ble        = BLEManager()
    @StateObject private var classifier = ClassifierCoordinator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    connectionHeader
                    emotionCard
                    todayCountsCard
                    historyCard
                }
                .padding()
            }
            .navigationTitle("DogSense")
        }
        .onAppear {
            ble.onAudioPacket = { [weak classifier] data in classifier?.handle(audioPacket: data) }
            ble.onIMUPacket   = { [weak classifier] data in classifier?.handle(imuPacket: data) }
        }
    }

    // MARK: - Subviews

    private var connectionHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ble.isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
            Text(ble.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Dog sound gate indicator
            if ble.isConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(classifier.isDogDetected ? Color.yellow : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(classifier.isDogDetected ? "Dog detected" : "Listening...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emotionCard: some View {
        VStack(spacing: 8) {
            Text("Today's Mood")
                .font(.headline)

            Text(classifier.detectionResult?.moodSummary ?? "Collecting baseline...")
                .font(.largeTitle.bold())
                .foregroundStyle(moodColor)
                .multilineTextAlignment(.center)

            Text(classifier.lastEmotionLabel == "—" ? "No events yet" : classifier.lastEmotionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let result = classifier.detectionResult, !result.flags.isEmpty {
                elevatedBadges(flags: result.flags)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var moodColor: Color {
        switch classifier.detectionResult?.moodSummary {
        case "Distressed":       return .red
        case "Anxious":          return .orange
        case "Excited / Playful": return .yellow
        case "Normal":           return .green
        default:                 return .primary
        }
    }

    private func elevatedBadges(flags: [String: String]) -> some View {
        let elevated = flags.filter { $0.value.contains("elevated") }.keys.sorted()
        return HStack(spacing: 6) {
            ForEach(elevated, id: \.self) { label in
                Text(label.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private var todayCountsCard: some View {
        let today = classifier.dailyLog.today
        let sorted = today.counts.sorted { $0.value > $1.value }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's Events")
                    .font(.headline)
                Spacer()
                Text("\(today.totalEvents) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sorted.isEmpty {
                Text("No events recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted, id: \.key) { label, count in
                    HStack {
                        Text(label.replacingOccurrences(of: "_", with: " "))
                            .font(.subheadline)
                        Spacer()
                        Text("\(count)")
                            .font(.subheadline.bold())
                            .foregroundStyle(color(for: label))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History (\(classifier.dailyLog.records.count) days)")
                .font(.headline)

            if classifier.dailyLog.records.isEmpty {
                Text("No history yet.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(classifier.dailyLog.records.reversed()) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.dateString)
                            .font(.caption.bold())
                        Text("\(record.totalEvents) events — " +
                             record.counts.sorted { $0.value > $1.value }
                                .prefix(3)
                                .map { "\($0.key.replacingOccurrences(of: "_", with: " ")): \($0.value)" }
                                .joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Color-code by arousal level
    private func color(for label: String) -> Color {
        if label.contains("High")   { return .red }
        if label.contains("Medium") { return .orange }
        return .blue
    }
}

#Preview {
    ContentView()
}
