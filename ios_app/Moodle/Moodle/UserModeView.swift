import SwiftUI

/// Owner-facing view — shows the dog's current emotional and activity state,
/// a 30-day stress calendar, and daily behavioural insights.
struct UserModeView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var classifier: ClassifierCoordinator
    @EnvironmentObject var profileStore: PuppyProfileStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                currentStatusCard
                calendarCard
                dailyStatsCard
                insightCard
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    if let img = profileStore.photo {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 75, height: 75)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 75, height: 75)
                            .overlay(
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color(.systemGray3))
                            )
                    }
                    Text(profileStore.profile.dogName.isEmpty ? "My Dog" : profileStore.profile.dogName)
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Current status

    private var currentStatusCard: some View {
        VStack(spacing: 14) {
            // Mood
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mood").font(.caption).foregroundStyle(.secondary)
                    Text(classifier.detectionResult?.moodSummary ?? "Collecting baseline…")
                        .font(.title.bold())
                        .foregroundStyle(moodColor)
                    if classifier.lastEmotionLabel != "—" {
                        Text(classifier.lastEmotionLabel.replacingOccurrences(of: "_", with: " "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                moodIcon
                    .font(.system(size: 44))
                    .foregroundStyle(moodColor.opacity(0.8))
            }

            Divider()

            // Activity
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity").font(.caption).foregroundStyle(.secondary)
                    if let o = classifier.latestOrientation {
                        HStack(spacing: 8) {
                            Image(systemName: o.committedLabel.symbolName)
                            Text(o.committedLabel.displayName)
                        }
                        .font(.title2.bold())
                        Text(activitySubtitle(o))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(ble.isConnected ? "Calibrating…" : "Not connected")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Anomaly badges
            if let flags = classifier.detectionResult?.flags {
                let elevated = flags.filter { $0.value.contains("elevated") }.keys.sorted()
                if !elevated.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(elevated, id: \.self) { label in
                                Text(label.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.red.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var moodColor: Color {
        switch classifier.detectionResult?.moodSummary {
        case "Distressed":         return .red
        case "Anxious":            return .orange
        case "Excited / Playful":  return .yellow
        case "Normal":             return .green
        default:                   return .secondary
        }
    }

    private var moodIcon: Text {
        switch classifier.detectionResult?.moodSummary {
        case "Distressed":         return Text("😟")
        case "Anxious":            return Text("😰")
        case "Excited / Playful":  return Text("🐾")
        case "Normal":             return Text("😊")
        default:                   return Text("💤")
        }
    }

    private func activitySubtitle(_ o: IMUOrientation) -> String {
        switch o.committedLabel {
        case .alert:    return "Head raised, on alert"
        case .resting:  return "Resting quietly"
        case .sniffing: return "Nose down, exploring"
        case .curious:  return "Head tilted, curious"
        case .active:   return "Moving around"
        case .running:  return "Running or playing"
        case .unknown:  return "Monitoring…"
        }
    }

    // MARK: - 30-day calendar

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30-Day Stress Calendar")
                .font(.headline)

            // Legend
            HStack(spacing: 16) {
                legendDot(.green,  "Normal")
                legendDot(.yellow, "Mild stress")
                legendDot(.red,    "Elevated stress")
                legendDot(Color(.systemGray4), "No data")
            }
            .font(.caption2)

            // Weekday headers
            let days = ["M", "T", "W", "T", "F", "S", "S"]
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    Text(d)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            calendarGrid
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var calendarGrid: some View {
        // Build last 30 days, padded so first day aligns to its weekday column
        let calendar = Calendar.current
        let today = Date()
        let dates: [Date] = (0..<30).compactMap {
            calendar.date(byAdding: .day, value: -(29 - $0), to: today)
        }

        // Leading padding to align first date to correct weekday (Mon=0 … Sun=6)
        let firstWeekday = (calendar.component(.weekday, from: dates[0]) + 5) % 7 // Mon-based
        let leadingEmpties = firstWeekday

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<leadingEmpties, id: \.self) { _ in
                Circle().fill(Color.clear).frame(height: 32)
            }
            ForEach(dates, id: \.self) { date in
                calendarDay(date: date)
            }
        }
    }

    private func calendarDay(date: Date) -> some View {
        let key = DayRecord.dateString(for: date)
        let record = classifier.dailyLog.records.first(where: { $0.dateString == key })
        let color = stressColor(for: record)
        let dayNum = Calendar.current.component(.day, from: date)
        let isToday = Calendar.current.isDateInToday(date)

        return ZStack {
            Circle()
                .fill(color)
                .frame(height: 32)
            if isToday {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: 1.5)
                    .frame(height: 32)
            }
            Text("\(dayNum)")
                .font(.caption2.bold())
                .foregroundStyle(color == Color(.systemGray4) ? Color.secondary : Color.white)
        }
        .frame(height: 32)
    }

    private func stressColor(for record: DayRecord?) -> Color {
        guard let record, record.totalEvents > 0 else { return Color(.systemGray4) }

        // Emotion-label based stress score
        let distress = (record.counts["High_Negative"]     ?? 0)
                     + (record.counts["Silent_Agitation"]  ?? 0)
        let mild     = (record.counts["Low_Negative"]      ?? 0)
                     + (record.counts["Medium_Negative"]   ?? 0)

        if distress > 5                   { return .red }
        if distress > 2 || mild > 8       { return .yellow }
        return .green
    }

    // MARK: - Daily stats

    private var dailyStatsCard: some View {
        let today = classifier.dailyLog.today

        return VStack(alignment: .leading, spacing: 12) {
            Text("Today's Summary").font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(icon: "waveform",
                         label: "Vocalizations",
                         value: "\(vocalCount(today))")
                statTile(icon: "figure.walk",
                         label: "Active Events",
                         value: "\(activityCount(today))")
                statTile(icon: "moon.zzz",
                         label: "Rest Events",
                         value: "\(today.counts["Resting"] ?? 0)")
                statTile(icon: "person.wave.2",
                         label: "Human Nearby",
                         value: "\(humanCount(today))")
            }

            if today.totalEvents > 0 {
                let pct = Int(100 * Float(activityCount(today)) /
                              max(1, Float(activityCount(today) + (today.counts["Resting"] ?? 0))))
                HStack {
                    Text("Active vs. rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)% active")
                        .font(.caption.bold())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * CGFloat(pct) / 100)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    // Count keys that belong to emotional vocalization labels
    private func vocalCount(_ record: DayRecord) -> Int {
        let vocalKeys = ["High_Negative","High_Neutral","High_Positive",
                         "Medium_Negative","Medium_Neutral","Medium_Positive",
                         "Low_Negative","Low_Neutral","Low_Positive"]
        return vocalKeys.reduce(0) { $0 + (record.counts[$1] ?? 0) }
    }

    // Count active IMU labels
    private func activityCount(_ record: DayRecord) -> Int {
        ["Active","Running","Alert","Curious","Sniffing"]
            .reduce(0) { $0 + (record.counts[$1] ?? 0) }
    }

    // Count speech detections (Apple's gate labels containing "speech")
    private func humanCount(_ record: DayRecord) -> Int {
        record.counts.filter { $0.key.lowercased().contains("speech") }
                     .values.reduce(0, +)
    }

    // MARK: - Smart insight

    private var insightCard: some View {
        let insight = generateInsight()
        guard !insight.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow)
                    .font(.title3)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Insight")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(insight)
                        .font(.subheadline)
                }
                Spacer()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        )
    }

    private func generateInsight() -> String {
        let today = classifier.dailyLog.today
        guard today.totalEvents > 0 else { return "" }

        let running  = today.counts["Running"]  ?? 0
        let active   = today.counts["Active"]   ?? 0
        let resting  = today.counts["Resting"]  ?? 0
        let distress = (today.counts["High_Negative"] ?? 0) + (today.counts["Silent_Agitation"] ?? 0)
        let vocal    = vocalCount(today)
        let human    = humanCount(today)

        if running > 15 {
            return "Very high activity today — looks like plenty of running and play time."
        }
        if distress > 8 {
            return "Multiple elevated distress signals today. Consider checking in on your dog."
        }
        if resting > 20 && active < 5 {
            return "Very low activity today. Lots of rest — check if this is unusual."
        }
        if human > 10 {
            return "Lots of human activity detected nearby. Social day!"
        }
        if vocal > 20 {
            return "High vocalization count today. Your dog was quite chatty."
        }
        if active + running > 20 {
            return "Active and energetic day overall."
        }
        return "A calm, normal day. Nothing unusual detected."
    }
}

#Preview {
    NavigationStack {
        UserModeView()
            .environmentObject(BLEManager(forPreview: true))
            .environmentObject(ClassifierCoordinator(forPreview: true))
            .environmentObject(PuppyProfileStore())
    }
}
