import Foundation

/// Parses 12-byte BLE IMU packets, maintains a calibrated orientation baseline,
/// and fires an IMUOrientation every 0.5 s (50-sample window, 50% overlap).
///
/// ## Activity label semantics
/// Every window produces a `displayLabel` (immediate, for live UI) and a
/// `committedLabel` (confirmed only after the activity has been sustained past
/// its per-label commit threshold). `isNewBout` is true only on the first
/// window where a new committed label takes effect — ClassifierCoordinator
/// uses this to log exactly one DailyLog entry per activity bout.
///
/// ## Calibration
/// The first 50 packets after reset() are averaged to establish the neutral
/// pitch/roll for the collar's resting position on this dog.
final class IMUBuffer {

    // MARK: - Configuration

    private let windowSize       = 50    // 1 s at 50 Hz
    private let slideSize        = 25    // 50% overlap → fires every 0.5 s
    private let rawBufferSize    = 100   // samples kept for Dev Mode graphs
    private let calibrationCount = 50   // packets before baseline is locked

    // MARK: - Raw motion thresholds

    private let pitchAlertDeg:    Float = 12.0  // ° above neutral → Alert candidate
    private let pitchSniffDeg:    Float = 12.0  // ° below neutral → Sniffing candidate
    private let rollCuriousDeg:   Float = 20.0  // |°| from neutral → Curious candidate
    private let activityActiveTh: Float = 0.30  // g RMS → Active candidate
    private let activityRunTh:    Float = 1.50  // g RMS → Running candidate
    private let agitationRestTh:  Float = 0.06  // g/s RMS → Resting candidate

    // MARK: - Commit thresholds (windows at 0.5 s each)
    // Minimum number of consecutive windows a raw label must hold before it
    // becomes the committedLabel and triggers a new bout log entry.

    private let commitThresholds: [ActivityLabel: Int] = [
        .running:  4,    //  2 s — a burst of strides, not a single jump
        .active:   6,    //  3 s — multiple steps, not a brief weight-shift
        .alert:    6,    //  3 s — sustained alertness, not a glance upward
        .sniffing: 10,   //  5 s — dogs genuinely nose-down for several seconds
        .curious:  4,    //  2 s — intentional head-tilt vs. random sway
        .resting:  120,  // 60 s — one full minute of stillness
        .unknown:  2,    //  1 s — fallthrough minimum
    ]

    // MARK: - State

    private var calibrationSamples: [[Float]] = []
    private var pitchBaseline: Float = 0
    private var rollBaseline:  Float = 0
    private(set) var isCalibrated = false

    private var window:    [[Float]] = []
    private var rawBuffer: [[Float]] = []

    // Pending/commit tracking
    private var pendingLabel:   ActivityLabel = .unknown
    private var pendingCount:   Int = 0
    private var committedLabel: ActivityLabel = .unknown

    // MARK: - Callbacks

    /// Fired on the caller's queue every ~0.5 s once calibrated.
    var onWindowReady: ((IMUOrientation) -> Void)?

    /// Fired on the caller's queue for every individual sample after calibration.
    /// Delivers raw (ax, ay, az, gx, gy, gz) for low-latency chart updates.
    var onSampleReady: ((Float, Float, Float, Float, Float, Float) -> Void)?

    // MARK: - Public API

    /// Call when BLE connects/disconnects to restart calibration and reset state.
    func reset() {
        calibrationSamples = []
        pitchBaseline      = 0
        rollBaseline       = 0
        isCalibrated       = false
        window             = []
        rawBuffer          = []
        pendingLabel       = .unknown
        pendingCount       = 0
        committedLabel     = .unknown
    }

    /// Parse one 12-byte BLE IMU packet.
    /// Format: 6 × big-endian int16 [ax×1000, ay×1000, az×1000, gx×10, gy×10, gz×10]
    func append(packet: Data) {
        guard packet.count == 12 else { return }

        let sample: [Float] = (0..<6).map { i in
            let raw = Int16(bitPattern: (UInt16(packet[i * 2]) << 8) | UInt16(packet[i * 2 + 1]))
            return Float(raw) / (i < 3 ? 1000.0 : 10.0)
        }

        // Calibration phase
        if !isCalibrated {
            calibrationSamples.append(sample)
            if calibrationSamples.count >= calibrationCount { calibrate() }
            return
        }

        // Per-sample callback for live chart updates (50 Hz)
        onSampleReady?(sample[0], sample[1], sample[2], sample[3], sample[4], sample[5])

        // Rolling raw buffer for Dev Mode graphs
        rawBuffer.append(sample)
        if rawBuffer.count > rawBufferSize {
            rawBuffer.removeFirst(rawBuffer.count - rawBufferSize)
        }

        // Inference window
        window.append(sample)
        if window.count >= windowSize {
            fireInference()
            window.removeFirst(slideSize)
        }
    }

    // MARK: - Calibration

    private func calibrate() {
        let n  = Float(calibrationSamples.count)
        let ax = calibrationSamples.map { $0[0] }.reduce(0, +) / n
        let ay = calibrationSamples.map { $0[1] }.reduce(0, +) / n
        let az = calibrationSamples.map { $0[2] }.reduce(0, +) / n

        pitchBaseline = atan2(ay, (ax*ax + az*az).squareRoot()) * (180 / .pi)
        rollBaseline  = atan2(-ax, az) * (180 / .pi)
        isCalibrated  = true
        calibrationSamples = []
    }

    // MARK: - Inference

    private func fireInference() {
        let samples = Array(window.prefix(windowSize))

        // Per-sample pitch and roll, zeroed to calibrated baseline
        let pitch = samples.map { s -> Float in
            atan2(s[1], (s[0]*s[0] + s[2]*s[2]).squareRoot()) * (180 / .pi) - pitchBaseline
        }.reduce(0, +) / Float(samples.count)

        let roll = samples.map { s -> Float in
            atan2(-s[0], s[2]) * (180 / .pi) - rollBaseline
        }.reduce(0, +) / Float(samples.count)

        // Mean |gz| — yaw angular velocity (deg/s)
        let yawRate = samples.map { abs($0[5]) }.reduce(0, +) / Float(samples.count)

        // RMS of |acc_magnitude − 1g| — movement energy above gravity
        let activityLevel: Float = {
            let sumSq = samples.map { s -> Float in
                let mag = (s[0]*s[0] + s[1]*s[1] + s[2]*s[2]).squareRoot()
                let dev = abs(mag - 1.0)
                return dev * dev
            }.reduce(0, +)
            return (sumSq / Float(samples.count)).squareRoot()
        }()

        // RMS jerk (consecutive acc-vector differences)
        let agitation: Float = {
            guard samples.count > 1 else { return 0 }
            let sumSq = zip(samples, samples.dropFirst()).map { a, b -> Float in
                let dx = b[0]-a[0], dy = b[1]-a[1], dz = b[2]-a[2]
                return dx*dx + dy*dy + dz*dz
            }.reduce(0, +)
            return (sumSq / Float(samples.count - 1)).squareRoot()
        }()

        // Immediate raw label — drives displayLabel
        let rawLabel = classify(pitch: pitch, roll: roll,
                                activityLevel: activityLevel, agitation: agitation)

        // Pending/commit logic
        if rawLabel == pendingLabel {
            pendingCount += 1
        } else {
            pendingLabel = rawLabel
            pendingCount = 1
        }

        let threshold     = commitThresholds[pendingLabel] ?? 4
        let justCommitted = pendingCount == threshold   // tipped over this window
        let isCommitted   = pendingCount >= threshold

        var isNewBout = false
        if isCommitted && pendingLabel != committedLabel {
            committedLabel = pendingLabel
            isNewBout = true
        } else if justCommitted && pendingLabel == committedLabel {
            // Already the same committed label — not a new bout
            isNewBout = false
        }

        let raw = rawBuffer
        let orientation = IMUOrientation(
            pitch: pitch, roll: roll, yawRate: yawRate,
            agitation: agitation, activityLevel: activityLevel,
            displayLabel:   rawLabel,
            committedLabel: committedLabel,
            isNewBout:      isNewBout,
            timestamp: Date(),
            rawAx: raw.map { $0[0] }, rawAy: raw.map { $0[1] }, rawAz: raw.map { $0[2] },
            rawGx: raw.map { $0[3] }, rawGy: raw.map { $0[4] }, rawGz: raw.map { $0[5] }
        )
        onWindowReady?(orientation)
    }

    // MARK: - Raw Label Classifier

    private func classify(pitch: Float, roll: Float,
                          activityLevel: Float, agitation: Float) -> ActivityLabel {
        if activityLevel > activityRunTh    { return .running }
        if activityLevel > activityActiveTh { return .active }
        if agitation < agitationRestTh      { return .resting }  // candidate only — commit needs 60 s
        if pitch >  pitchAlertDeg           { return .alert }
        if pitch < -pitchSniffDeg           { return .sniffing }
        if abs(roll) > rollCuriousDeg       { return .curious }
        return .unknown
    }
}
