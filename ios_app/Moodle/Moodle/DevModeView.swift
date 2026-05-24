import SwiftUI
import Charts

/// Developer view — shows every live sensor stream and classification output.
/// Intended for live demos and debugging, not for end users.
struct DevModeView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var classifier: ClassifierCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                if !ble.isConnected {
                    notConnectedBanner
                } else {
                    // Audio
                    audioWaveformCard
                    soundClassificationCard

                    // IMU
                    orientationCard
                    accelerometerCard
                    gyroscopeCard
                    activityCard
                }
            }
            .padding()
        }
        .navigationTitle("Dev Mode")
    }

    // MARK: - Not connected

    private var notConnectedBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Connect to DogSense to see live sensor data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Audio waveform

    private var audioWaveformCard: some View {
        let waveform = classifier.audioWaveform
        let peak = waveform.max() ?? 0
        let scale: Float = peak > 0.001 ? 1.0 / peak : 1.0

        return DevCard(title: "Audio Stream", badge: String(format: "peak %.4f", peak)) {
            HStack(alignment: .bottom, spacing: 1.5) {
                if waveform.isEmpty {
                    Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ForEach(Array(waveform.enumerated()), id: \.offset) { _, s in
                        let n = CGFloat(s * scale)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(n))
                            .frame(maxWidth: .infinity, minHeight: 2)
                            .frame(height: max(2, n * 80))
                    }
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func barColor(_ n: CGFloat) -> Color {
        n > 0.75 ? .red : n > 0.4 ? .orange : .green
    }

    // MARK: - Sound classification

    private var soundClassificationCard: some View {
        DevCard(title: "Level 1 — Sound Gate",
                badge: classifier.isDogDetected ? "DOG DETECTED" : "listening",
                badgeColor: classifier.isDogDetected ? .green : .secondary) {
            if classifier.gateClassifications.isEmpty {
                Text("Waiting for classifications…").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(classifier.gateClassifications) { item in
                    HStack(spacing: 8) {
                        Text(item.label.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(item.isDog ? .primary : .secondary)
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.isDog ? Color.yellow : Color.gray.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(item.confidence))
                        }
                        .frame(height: 8)
                        Text(String(format: "%.0f%%", item.confidence * 100))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .frame(height: 20)
                }

                if classifier.lastEmotionLabel != "—" {
                    Divider().padding(.vertical, 4)
                    HStack {
                        Text("Level 2 — Emotion")
                            .font(.caption.bold())
                        Spacer()
                        Text(classifier.lastEmotionLabel.replacingOccurrences(of: "_", with: " "))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(String(format: "%.0f%%", classifier.lastEmotionConfidence * 100))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Orientation readout

    private var orientationCard: some View {
        DevCard(title: "Head Orientation",
                badge: classifier.imuBuffer.isCalibrated ? "calibrated" : "calibrating…",
                badgeColor: classifier.imuBuffer.isCalibrated ? .green : .orange) {
            if let o = classifier.latestOrientation {
                HStack(spacing: 0) {
                    orientationStat(label: "Pitch", value: o.pitch, unit: "°",
                                    color: pitchColor(o.pitch))
                    Divider().frame(height: 44)
                    orientationStat(label: "Roll",  value: o.roll,  unit: "°",
                                    color: .blue)
                    Divider().frame(height: 44)
                    orientationStat(label: "Yaw Rate", value: o.yawRate, unit: "°/s",
                                    color: .purple)
                    Divider().frame(height: 44)
                    orientationStat(label: "Agitation", value: o.agitation, unit: "g/s",
                                    color: agitationColor(o.agitation))
                }
                .frame(maxWidth: .infinity)
            } else {
                Text(classifier.imuBuffer.isCalibrated ? "Waiting for window…" : "Hold still — calibrating baseline…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func orientationStat(label: String, value: Float, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%+.1f", value))
                .font(.title3.bold().monospaced())
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func pitchColor(_ p: Float) -> Color {
        if p > 12  { return .green }
        if p < -12 { return .orange }
        return .primary
    }

    private func agitationColor(_ a: Float) -> Color {
        if a > 0.5 { return .red }
        if a > 0.2 { return .orange }
        return .green
    }

    // MARK: - Accelerometer chart

    private var accelerometerCard: some View {
        let raw = classifier.liveIMURaw
        return DevCard(title: "Accelerometer", badge: "g") {
            if !raw.ax.isEmpty {
                imuChart(
                    a: raw.ax, b: raw.ay, c: raw.az,
                    aLabel: "ax", bLabel: "ay", cLabel: "az",
                    yDomain: -1.5...1.5
                )
            } else {
                placeholderChart
            }
        }
    }

    // MARK: - Gyroscope chart

    private var gyroscopeCard: some View {
        let raw = classifier.liveIMURaw
        return DevCard(title: "Gyroscope", badge: "dps") {
            if !raw.gx.isEmpty {
                imuChart(
                    a: raw.gx, b: raw.gy, c: raw.gz,
                    aLabel: "gx", bLabel: "gy", cLabel: "gz",
                    yDomain: -250...250
                )
            } else {
                placeholderChart
            }
        }
    }

    // MARK: - Activity label

    private var activityCard: some View {
        DevCard(title: "Activity Classification", badge: "IMU") {
            if let o = classifier.latestOrientation {
                VStack(alignment: .leading, spacing: 10) {
                    // Confirmed (committed) label — prominent
                    HStack(spacing: 16) {
                        Image(systemName: o.committedLabel.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.committedLabel.displayName)
                                .font(.title2.bold())
                            Text("confirmed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // Candidate (display) label — shows what the classifier sees right now
                    HStack(spacing: 8) {
                        Image(systemName: o.displayLabel.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("candidate: \(o.displayLabel.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if o.displayLabel == o.committedLabel {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 12) {
                        statChip(label: "activity", value: String(format: "%.2fg", o.activityLevel))
                        statChip(label: "agitation", value: String(format: "%.2f", o.agitation))
                        if o.isNewBout {
                            statChip(label: "bout", value: "NEW")
                        }
                    }
                }
            } else {
                Text("Waiting for IMU window…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func statChip(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.bold().monospaced())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Shared chart helper

    private func imuChart(a: [Float], b: [Float], c: [Float],
                           aLabel: String, bLabel: String, cLabel: String,
                           yDomain: ClosedRange<Double>) -> some View {
        Chart {
            axisMarks(values: a, label: aLabel, color: .red)
            axisMarks(values: b, label: bLabel, color: .green)
            axisMarks(values: c, label: cLabel, color: .blue)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartLegend(position: .trailing, alignment: .center)
        .frame(height: 110)
    }

    @ChartContentBuilder
    private func axisMarks(values: [Float], label: String, color: Color) -> some ChartContent {
        ForEach(Array(values.enumerated()), id: \.offset) { i, v in
            LineMark(
                x: .value("t", i),
                y: .value(label, Double(v))
            )
            .foregroundStyle(by: .value("axis", label))
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
    }

    private var placeholderChart: some View {
        Text("Waiting for IMU data…")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 110)
    }
}

// MARK: - DevCard container

private struct DevCard<Content: View>: View {
    let title: String
    var badge: String = ""
    var badgeColor: Color = .secondary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(badgeColor.opacity(0.12), in: Capsule())
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        DevModeView()
            .environmentObject(BLEManager(forPreview: true))
            .environmentObject(ClassifierCoordinator(forPreview: true))
    }
}
