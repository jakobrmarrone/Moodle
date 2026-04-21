# Plan: IMU + Audio Emotion Fusion for Moodle

## Context
The project already has a working two-stage audio pipeline (bark gate → DogArousalValence 9-class emotion model). The IMU side currently only runs a Random Forest posture classifier that isn't wired into the UI. The goal is to fuse the BMI270 IMU signal with the audio emotion output to produce a richer, more confident emotional state — and to detect silent distress (agitation between barks) that the audio model cannot catch.

No new labeled data will be collected (beyond a possible n=1 session). The fusion will be rule-based, grounded in ethology, so no training data is required.

---

## Approach: Head Orientation + Rule-Based Fusion

### Why this works without training data
- **Pitch** (head raised/lowered) is derived from the accelerometer gravity vector via trigonometry — no ML needed
- **Roll** (head tilt) is the same
- **Agitation index** (jerk magnitude) = norm of the per-sample acceleration derivative — pure signal math
- **Relative yaw rate** = gyroscope z-axis angular velocity
- These four signals map directly onto the arousal/valence axes the audio model already uses:
  - Pitch ↑ → high arousal (raised head = alert, excited, or distressed)
  - Pitch ↓ → low arousal (head down = submissive, anxious, resting)
  - High jerk → negative or high arousal (agitation)
  - Head tilt (roll) → attentional/curious (positive valence correlate)
  - High yaw rate → scanning, unsettled

### No existing public paired (audio + IMU + emotion label) dog dataset found
The EmotionalCanines dataset (which trained DogArousalValence.mlmodel) is audio-only. No public dataset pairs collar IMU with emotional vocalization labels. Rule-based fusion is therefore the correct approach now, with the option to learn weights later from n=1 data if collected.

---

## Implementation Plan

### Step 1 — IMU: Compute head orientation angles in `IMUBuffer.swift`

Replace or augment the current mean/std feature window with continuous per-packet orientation estimates:

**Pitch** (head raise/lower, in degrees):
```
pitch = atan2(ay, sqrt(ax² + az²)) * (180/π)
```
- Positive pitch = nose up
- Negative pitch = nose down

**Roll** (head tilt, in degrees):
```
roll = atan2(-ax, az) * (180/π)
```

**Agitation index** (RMS jerk over window):
```
jerk[i] = sqrt((ax[i]-ax[i-1])² + (ay[i]-ay[i-1])² + (az[i]-az[i-1])²)
agitation = rms(jerk[0..N])
```

**Yaw rate** (mean absolute gyroscope z over window):
```
yawRate = mean(|gz[0..N]|)
```

These four values replace (or supplement) the existing 12-float feature vector.
Publish them as `IMUOrientation` struct via `onWindowReady` callback.

### Step 2 — New struct: `IMUOrientation`
```swift
struct IMUOrientation {
    let pitch: Float        // degrees, + = head raised
    let roll: Float         // degrees, + = right tilt
    let agitation: Float    // 0+, RMS jerk (g/s)
    let yawRate: Float      // deg/s, mean absolute
    let timestamp: Date
}
```

### Step 3 — New class: `EmotionFuser.swift`

Receives:
- `audioLabel: String` (e.g. "High_Negative") + `audioConfidence: Float`
- `orientation: IMUOrientation`
- `isDogDetected: Bool`

Outputs:
- `fusedLabel: String` — same 9-class space, or "Silent_Agitation"
- `fusedConfidence: Float` — boosted or discounted
- `imuContext: String` — human-readable ("head raised", "head tilted", "agitated", "calm")

**Fusion rules (ethology-grounded):**

| Condition | Effect |
|---|---|
| Audio fires + pitch > +12° (raised head) | Boost confidence by +0.10 if High_* label |
| Audio fires + pitch < -10° (head down) | Boost confidence by +0.10 if Low_Negative; discount if High_Positive |
| Audio fires + agitation > threshold | Boost confidence if *_Negative; discount if *_Positive |
| Audio fires + roll > ±15° (head tilt) | Boost confidence by +0.08 if *_Positive (curiosity correlate) |
| Audio silent + agitation > threshold + pitch < -8° | Emit "Silent_Agitation" event (dog is distressed but not vocalizing) |
| All IMU signals calm + Audio silence | No event (true rest) |

Confidence capped at 0.99. Thresholds tunable as constants.

### Step 4 — Wire into `ClassifierCoordinator.swift`
- Replace `updateDetection()` call with `EmotionFuser.fuse(audioResult:orientation:)`
- Store latest `IMUOrientation` as a property, updated by `imuBuffer.onWindowReady`
- Publish `fusedLabel`, `fusedConfidence`, `imuContext` as `@Published` properties

### Step 5 — Update `ContentView.swift` Level 2 Card
- Show `imuContext` string as a subtitle ("Head raised · calm")
- Show fused confidence vs audio-only confidence (small secondary label)
- Add "Silent Agitation" detection as its own badge/row in Today's Events
- Small pitch/agitation indicator (e.g., a simple bar or icon showing head position)

### Step 6 — Update `DailyLog.swift`
- Add "Silent_Agitation" as a loggable label alongside the 9 audio emotion classes
- This gives a fuller picture: dog may have 3 High_Negative bark events + 12 Silent_Agitation events in a day

---

## Files to Modify

| File | Change |
|---|---|
| `ios_app/Moodle/Moodle/IMUBuffer.swift` | Add pitch/roll/agitation/yawRate computation, output `IMUOrientation` |
| `ios_app/Moodle/Moodle/ClassifierCoordinator.swift` | Store latest `IMUOrientation`, call `EmotionFuser` |
| `ios_app/Moodle/Moodle/ContentView.swift` | Update Level 2 card with imuContext + fused confidence |
| `ios_app/Moodle/Moodle/DailyLog.swift` | Add "Silent_Agitation" as valid label |

## New Files to Create

| File | Purpose |
|---|---|
| `ios_app/Moodle/Moodle/IMUOrientation.swift` | Struct definition |
| `ios_app/Moodle/Moodle/EmotionFuser.swift` | Rule-based fusion logic + constants |

---

## Calibration Note
Pitch/roll angles assume the device is mounted at the collar with the sensor axes known. The accelerometer gravity offset at rest (when dog is standing neutral) should be zeroed on first connection (or after a 2-second still period). This prevents breed-specific neck angle from skewing the pitch baseline.

A simple auto-calibration: average the first 50 IMU packets after "streaming started" and store as the neutral offset.

---

## Verification
1. Flash firmware, connect iOS app, hold device level → pitch should read ~0°
2. Tilt device nose-up → pitch goes positive; nose-down → negative
3. Tilt device sideways → roll changes, pitch stays ~same
4. Shake device vigorously → agitation index spikes
5. Trigger a bark (play audio near mic) with device nose-up → fused confidence should be higher than audio-only confidence for High_* labels
6. No barking + shake device → "Silent_Agitation" event should appear in Today's Events
