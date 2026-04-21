# Session Notes — April 17, 2026

## Goal
Improve BLE streaming smoothness for live demo, fix IMU axis orientation, and clarify architecture documentation.

---

## 1. BLE Streaming Latency Investigation

Identified four root causes of streaming lag:

### Connection Interval (`main.cpp`)
Added `BLE.setConnectionInterval(8, 8)` before `BLE.advertise()` to request a 10ms connection interval (8 × 1.25ms) from iOS. Without this, iOS negotiates a conservative ~30ms default, causing the firmware TX queue to back up when sending 100 audio notifications/sec.

### CBCentralManager on Main Thread (`BLEManager.swift`)
`CBCentralManager` was initialized on `.main`, meaning all BLE callbacks (including ~100 audio packets/sec) competed directly with SwiftUI rendering. Moved to a dedicated `DispatchQueue(label: "com.moodle.ble", qos: .userInitiated)`. All `@Published` property mutations in delegate callbacks were wrapped with `DispatchQueue.main.async`.

### Audio Packet Rate (`ble_config.h`)
Reduced notification rate from 100/sec to ~80/sec by increasing the PDM window from 10ms (160 bytes) to 12.5ms (200 bytes). This stays well under the 247-byte BLE max and gives the stack breathing room alongside IMU packets. `AUDIO_PACKET_BYTES` changed 160 → 200, `PDM_BUFFER_BYTES` changed 320 → 400. `MuLawDecoder` and `AudioBuffer` required no changes — both are fully data-driven on packet size.

---

## 2. IMU Display Lag Investigation

Determined the IMU display lag was not a BLE issue. The `onWindowReady` callback in `IMUBuffer` fires every 0.5s (50-sample window, 25-sample slide at 50Hz), meaning the UI could only refresh orientation data at 2Hz regardless of BLE latency.

### First attempt (reverted): fast pitch/roll/yaw
Added `onSampleReady` callback firing at 50Hz with derived pitch/roll/yawRate. Wired to a `liveOrientation` published property in `ClassifierCoordinator`. Updated `DevModeView.orientationCard` to use it. User confirmed the header updated faster but charts were still laggy — and said they didn't need pitch/roll/yaw updating fast.

### Final fix: fast raw axis arrays for charts
Repurposed `onSampleReady` to pass raw axis values `(ax, ay, az, gx, gy, gz)` instead of derived angles. In `ClassifierCoordinator`, added a `LiveIMURaw` struct with 6 rolling `[Float]` arrays (capped at 100 entries), updated as a single struct assignment per sample (one `objectWillChange` at 50Hz, coalesced by SwiftUI to display refresh rate). Updated `DevModeView` accelerometer and gyroscope cards to read from `classifier.liveIMURaw`. Orientation card reverted to `latestOrientation` (0.5s is acceptable for pitch/roll readout).

---

## 3. IMU Axis Orientation Fix

### Diagnosis
User reported the accelerometer chart's x and y axes appeared swapped. Investigated whether this was a display label issue or a semantic issue by asking the user to observe pitch/roll behavior during physical tilts.

User reported:
- Tilting collar nose-down (rotating about x-axis) → pitch became **positive**
- Rotating about y-axis → roll changed
- Rotating about z-axis → yaw rate changed

This confirmed a semantic issue: `IMUBuffer` classifies `pitch < -12°` as Sniffing and `pitch > +12°` as Alert, but nose-down was producing positive pitch — meaning sniffing would never trigger and alert would fire when the dog's nose went down.

### Fix (`main.cpp`)
Negated `ay` in `buildImuPacket()`:
```cpp
(int16_t)(-ay * 1000.0f)
```
This flips the sign convention so nose-down correctly produces negative pitch throughout the entire pipeline — calibration, feature extraction, threshold classification, and activity labeling all inherit the fix automatically.

---

## 4. Architecture Documentation

### IMU pipeline explanation
Clarified that the IMU classifier is entirely threshold-based (no ML model involved at runtime):
- 5 scalar features computed per 1s window: pitch, roll, yaw rate, activity level (accel RMS above 1g), agitation (jerk RMS)
- Priority threshold chain: Running > Active > Resting > Alert > Sniffing > Curious > Unknown
- Commit hysteresis gates `DailyLog` writes: labels must be sustained 2–60s before a new bout is logged (Resting requires 60s)
- Yaw rate is computed and displayed but unused by the classifier

### Mermaid diagram updates
Updated the project's system architecture Mermaid diagram. The original IMU_PIPE subgraph incorrectly referenced the unused Python training scripts ("mean + std per axis → 12-float feature vector", "Random Forest → CoreML"). Replaced with the accurate implementation: sliding window → threshold classifier → activity label → commit hysteresis → DailyLog. Also added the missing `AL → DL` connection (activity labels feed the daily log alongside emotion labels).

---

## Files Modified

| File | Change |
|---|---|
| `src/main.cpp` | Added `BLE.setConnectionInterval(8, 8)`; negated `ay` in `buildImuPacket()` |
| `include/ble_config.h` | `AUDIO_PACKET_BYTES` 160→200, `PDM_BUFFER_BYTES` 320→400 |
| `ios_app/.../BLEManager.swift` | Moved `CBCentralManager` to background queue; wrapped all `@Published` mutations in `main.async` |
| `ios_app/.../IMUBuffer.swift` | Added `onSampleReady` callback firing raw axis values at 50Hz |
| `ios_app/.../ClassifierCoordinator.swift` | Added `LiveIMURaw` struct + `@Published var liveIMURaw`; wired `onSampleReady` |
| `ios_app/.../DevModeView.swift` | Accel/gyro charts now read from `liveIMURaw`; orientation card reads from `latestOrientation` |
