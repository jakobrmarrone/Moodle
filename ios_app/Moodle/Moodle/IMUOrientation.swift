import Foundation

// MARK: - Activity Label

enum ActivityLabel: String, CaseIterable, Codable {
    case alert    = "Alert"
    case resting  = "Resting"
    case sniffing = "Sniffing"
    case curious  = "Curious"
    case active   = "Active"
    case running  = "Running"
    case unknown  = "—"

    /// Short description shown in the UI.
    var displayName: String { rawValue }

    /// SF Symbol name associated with this activity.
    var symbolName: String {
        switch self {
        case .alert:    return "eyes"
        case .resting:  return "moon.zzz"
        case .sniffing: return "nose"
        case .curious:  return "questionmark.circle"
        case .active:   return "figure.walk"
        case .running:  return "hare"
        case .unknown:  return "minus"
        }
    }
}

// MARK: - IMU Orientation

/// Computed orientation and motion features derived from one 1-second IMU window,
/// plus raw per-axis rolling buffers for live graphing in Dev Mode.
struct IMUOrientation {
    // -- Orientation angles (degrees, relative to calibrated neutral) --
    let pitch: Float        // + = nose up,  − = nose down
    let roll: Float         // + = right tilt, − = left tilt
    let yawRate: Float      // deg/s — mean |gz| over the window

    // -- Motion features --
    let agitation: Float    // RMS jerk (g/s) — proxy for distress / excitability
    let activityLevel: Float // RMS of |acc_magnitude − 1 g| — overall movement energy

    // -- Classification --
    /// Immediate label — updates every window. Use for live display only.
    let displayLabel: ActivityLabel
    /// Confirmed label — only set after the activity is sustained past its commit threshold.
    let committedLabel: ActivityLabel
    /// True only on the first window where the committed label transitions to a new state.
    /// ClassifierCoordinator uses this to log exactly one DailyLog entry per bout.
    let isNewBout: Bool

    let timestamp: Date

    // -- Raw rolling buffers (last ~100 samples) for Dev Mode graphs --
    let rawAx: [Float]
    let rawAy: [Float]
    let rawAz: [Float]
    let rawGx: [Float]
    let rawGy: [Float]
    let rawGz: [Float]
}
