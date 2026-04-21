# Session Notes — April 13, 2026

## What Was Accomplished

### 1. IMU Orientation Foundation (`IMUOrientation.swift` — new)
- Created the `IMUOrientation` struct that carries all computed IMU features per inference window: pitch, roll, yaw rate, agitation index, activity level, activity label, timestamp, and raw per-axis buffers (ax/ay/az/gx/gy/gz) for graphing.
- Created the `ActivityLabel` enum with six states: `alert`, `resting`, `sniffing`, `curious`, `active`, `running`. Each case has a `displayName` and an SF Symbol (`symbolName`) for UI use. Conforms to `Codable` so it can be stored in DailyLog.

### 2. IMU Buffer Rewrite (`IMUBuffer.swift` — full rewrite)
- **Replaced** the old mean/std feature vector pipeline (which fed a never-integrated Random Forest CoreML model) with a self-contained threshold-based classifier.
- **Auto-calibration**: first 50 packets after `reset()` are averaged to establish neutral pitch/roll baseline. Accounts for breed-specific collar angle and board mounting orientation. IMU is silent (no window fires) until calibration completes.
- **Pitch** computed per sample via `atan2(ay, √(ax²+az²))`, zeroed to baseline.
- **Roll** computed per sample via `atan2(-ax, az)`, zeroed to baseline.
- **Agitation index**: RMS of consecutive acc-vector differences (jerk). High values = sudden movement / distress.
- **Activity level**: RMS of `|acc_magnitude − 1g|`. Isolates movement above gravity.
- **Yaw rate**: mean `|gz|` over the window — head-turning speed.
- **Raw rolling buffer**: last 100 raw samples kept separately for Dev Mode graph rendering. Snapshot taken at each window fire.
- **Threshold classifier** (all constants defined at top, easy to tune):
  - Running: activity level > 1.50g
  - Active: activity level > 0.30g
  - Resting: agitation < 0.06 g/s for 3 consecutive windows (sustained calm required)
  - Alert: pitch > +12° above baseline
  - Sniffing: pitch < −12° below baseline
  - Curious: |roll| > 20° from baseline
  - Unknown: fallthrough

### 3. ClassifierCoordinator Update (`ClassifierCoordinator.swift`)
- Added `@Published var latestOrientation: IMUOrientation?` — published every ~0.5s when a window fires.
- Added `setupIMU()` which sets `imuBuffer.onWindowReady` callback. On each window: updates `latestOrientation`, logs the activity label to `DailyLog`, and runs outlier detection.
- Added `resetIMUCalibration()` — callable when BLE reconnects to restart the 50-packet calibration phase.
- Activity labels are logged into `DailyLog` alongside emotion labels using the same `increment(label:)` API. DailyLog's `[String: Int]` dict accepts arbitrary strings so no schema change was needed.

### 4. Arduino Serial Diagnostic (`src/main.cpp`)
- Added a 5Hz (every 200ms) Serial print loop that outputs pitch, roll, and all 6 raw IMU axes to Serial Monitor.
- Output format: `pitch:+12.4  roll:-3.1  ax:0.02  ay:0.98  az:0.10  gx:0.5  gy:0.1  gz:-0.3`
- **Why**: the BMI270 axis orientation relative to the physical collar mount is unknown until verified empirically. This lets you open Serial Monitor, tilt the board nose-up/down/sideways, and confirm which axis drives pitch and roll before trusting the iOS output.
- Fixed the `while (!Serial)` blocking call — changed to `while (!Serial && millis() < 3000)` so the firmware boots normally after 3s even without a USB host connected (previously it would hang indefinitely without Serial Monitor open).

### 5. Dev Mode View (`DevModeView.swift` — new)
- Full live sensor dashboard intended for class demos and debugging.
- **Audio waveform card**: same rolling peak bar graph as the old ContentView.
- **Sound classification card**: top-5 gate classifications with confidence bars + live Level 2 emotion label when dog detected.
- **Head orientation card**: pitch / roll / yaw rate / agitation displayed as four numerical readouts. Badge shows calibration state.
- **Accelerometer chart**: SwiftUI Charts `LineMark` for ax (red), ay (green), az (blue) over last 100 samples. Y-domain ±2.5g.
- **Gyroscope chart**: same pattern for gx/gy/gz. Y-domain ±250 dps.
- **Activity classification card**: large SF Symbol + label name + activity level and agitation chips.
- All cards use a shared `DevCard` container component for consistent styling.

### 6. User Mode View (`UserModeView.swift` — new)
- **Current status card**: mood (from OutlierDetector) + emoji, last emotion label, current activity label with subtitle description, anomaly badges if any labels are elevated.
- **30-day stress calendar**: `LazyVGrid` with 7 columns (Mon–Sun). Each day is a colored circle:
  - Red: `High_Negative` + `Silent_Agitation` count > 5
  - Yellow: distress > 2 or `Low_Negative`/`Medium_Negative` > 8
  - Green: data present, no stress threshold exceeded
  - Gray: no data for that day
  - Today has a primary-color stroke ring.
  - Leading empty cells pad the grid so the first date aligns to its correct weekday column.
- **Daily stats tiles**: vocalization count, active events, rest events, human nearby (speech detections from Apple's classifier). Active vs. rest percentage bar.
- **Smart insight**: rule-based one-line summary generated from today's counts (e.g., "Very high activity today", "Multiple distress signals detected", "Lots of human activity").

### 7. ContentView Refactor (`ContentView.swift`)
- Replaced the old single-scroll card stack with a `TabView` containing two tabs.
- "My Dog" tab (pawprint icon) → `UserModeView`
- "Dev" tab (waveform magnify icon) → `DevModeView`
- Both tabs wrapped in their own `NavigationStack` so each has an independent nav bar.
- Shared connection button (status dot + Connect/Disconnect) lives in the navigation bar trailing item, injected via `@ToolbarContentBuilder` and reused in both tabs.
- Both child views receive `BLEManager` and `ClassifierCoordinator` via `.environmentObject()`.

---

## Dependencies & Assumptions

### Axis orientation (critical — verify with Serial Monitor first)
The pitch/roll formulas assume:
- `ay` is the axis pointing along the dog's spine (toward the head when head is raised)
- `az` is the axis perpendicular to the board face

This is the standard BMI270 orientation when the Arduino Nano 33 BLE Sense is mounted flat, component-side up. If the board is mounted sideways or inverted in the enclosure, the axis assignments in `IMUBuffer.classify()` will need to be swapped. **Use the Serial diagnostic before trusting iOS output.**

### Calibration window (first 50 packets = 1 second)
The auto-calibration assumes the collar is sitting in its natural resting position on the dog's neck for the first second after connecting. If the dog is running or the board is being handled during that window, the baseline will be wrong. Call `resetIMUCalibration()` (via `classifier.resetIMUCalibration()`) to redo it.

### DailyLog schema
Activity labels (`"Alert"`, `"Resting"`, etc.) are stored in the same `[String: Int]` dict as emotion labels. The User Mode stat tiles filter by known key names. If label strings ever change, the stat tile filters must be updated in sync.

### SwiftUI Charts (iOS 16+)
`DevModeView` imports `Charts`. The project already targets iOS 16+, so no additional dependency is needed. Charts is a native framework — no SPM package required.

### `@EnvironmentObject` injection
`UserModeView` and `DevModeView` both use `@EnvironmentObject var ble: BLEManager` and `@EnvironmentObject var classifier: ClassifierCoordinator`. These are injected by `ContentView` via `.environmentObject()`. If either view is instantiated outside that chain (e.g., in a new preview or a different root), it will crash unless environment objects are explicitly provided.

### `Silent_Agitation` label (planned, not yet emitted)
The session plan and CLAUDE.md reference a `"Silent_Agitation"` label to be emitted when the dog shows agitation without vocalizing. This label is accounted for in `stressColor()` in `UserModeView` but **is not yet emitted by any code path**. It is a future addition to `ClassifierCoordinator` (EmotionFuser step from the saved plan).

### Thresholds are not validated against real data
All activity classification thresholds (`pitchAlertDeg`, `activityRunTh`, etc.) in `IMUBuffer.swift` are educated estimates. They will need empirical tuning once the device is worn by a dog. The constants are defined at the top of the class for easy adjustment.

### Human interaction detection
`humanCount()` in `UserModeView` counts DailyLog entries where the key contains `"speech"`. Apple's `.version1` classifier does detect speech as a class, but it cannot distinguish whether the speech is directed at the dog. This is noted as a known limitation in CLAUDE.md.

---

## What Remains (from the saved plan)

- **EmotionFuser** (`EmotionFuser.swift`) — rule-based fusion of audio emotion + IMU orientation into a single boosted confidence label, and `Silent_Agitation` detection. Designed but not yet implemented.
- **Threshold tuning** — all IMU thresholds need real-world validation with a dog wearing the device.
- **BLE reconnect logic** — `BLEManager` still does not auto-reconnect on peripheral drop.
- **Info.plist BLE strings** — still empty, needed for App Store.
