# Moodle — Dog Emotional State Monitor

**Cal Poly SLO Biomedical Engineering Senior Project.**
A dog wearable that streams audio + IMU over BLE to an iOS app for real-time emotional state classification using a two-stage ML pipeline.

---

## Project Layout

```
LED BLINK/
├── src/main.cpp                        # Arduino Nano 33 BLE Sense firmware
├── include/
│   ├── ble_config.h                    # BLE UUIDs, packet sizes, command bytes
│   └── mulaw.h                         # G.711 µ-law encoder (firmware side)
├── platformio.ini                      # PlatformIO build config
├── ios_app/Moodle/Moodle/
│   ├── DogSenseApp.swift               # SwiftUI app entry point
│   ├── ContentView.swift               # Main UI (cards: connection, waveform, L1, L2, history)
│   ├── BLEManager.swift                # BLE scan/connect/notify/command
│   ├── ClassifierCoordinator.swift     # Two-stage ML orchestration
│   ├── AudioBuffer.swift               # µ-law decode → AVAudioPCMBuffer → SNAnalyzer
│   ├── MuLawDecoder.swift              # 256-entry lookup table decode
│   ├── IMUBuffer.swift                 # 1s/50% window → 12-float feature vector
│   ├── DailyLog.swift                  # Persistent 30-day rolling emotion counts
│   ├── OutlierDetector.swift           # Per-label Z-score anomaly detection
│   └── Resources/DogArousalValence.mlmodel
├── data_collection/collector.py        # BLE data capture → WAV + CSV
├── training/
│   ├── extract_yamnet_embeddings.py    # YAMNet → (N, 1024) .npz
│   ├── train_vocal_classifier.py       # Keras head on frozen embeddings
│   ├── train_posture_classifier.py     # Random Forest on IMU features
│   ├── export_yamnet_coreml.py         # TF → CoreML export
│   └── CreateML_Dataset/              # Train/Test split for DogArousalValence
│       └── {Train,Test}/
│           └── {High,Medium,Low}_{Negative,Neutral,Positive}/
└── README.md
```

---

## Hardware

- **MCU:** Arduino Nano 33 BLE Sense (Nordic nRF52840)
- **Microphone:** onboard PDM mic — 16 kHz mono, 160 samples/packet (10 ms), µ-law encoded
- **IMU:** BMI270 (Arduino_BMI270_BMM150 library) — 6 DOF at 50 Hz
- **BLE:** ArduinoBLE v1.3.7, max notification payload 247 bytes (`-DBLE_ATTRIBUTE_MAX_VALUE_LENGTH=247`)

### BLE GATT Layout

| Characteristic | UUID | Properties | Size |
|---|---|---|---|
| Service | `8d8439b3-...` | — | — |
| Audio | `6aefa1e2-...` | Notify | 160 bytes |
| IMU | `66c1f950-...` | Notify | 12 bytes |
| Command | `a5568574-...` | Write | 1 byte |

Commands: `0x01` = start streaming, `0x00` = stop streaming.

### IMU Packet Format (12 bytes, big-endian int16)
```
[ax*1000, ay*1000, az*1000, gx*10, gy*10, gz*10]
```
Divide accel by 1000 → g, gyro by 10 → dps.

---

## ML Pipeline

### Philosophy
Two-stage, power-aware design:
1. **Stage 1 (Gate):** Apple's built-in `SNClassifySoundRequest(.version1)` — always running, filters for dog sounds.
2. **Stage 2 (Emotion):** `DogArousalValence.mlmodel` — only runs inference when the gate fires.

### Emotion Model — Valence × Arousal Grid

The model outputs **9 classes** derived from the EmotionalCanines dataset:

| | Negative | Neutral | Positive |
|---|---|---|---|
| **High** | Distressed bark | — | Excited/play |
| **Medium** | — | — | — |
| **Low** | Anxious/whine | — | — |

Classes follow the naming convention: `{High,Medium,Low}_{Negative,Neutral,Positive}`

### Training Data & Model Training
- Dataset: **EmotionalCanines** (2025 ACM Multimedia) — arousal/valence annotated dog vocalizations
- Labels were manually reformatted to match Create ML's expected directory naming convention (`{High,Medium,Low}_{Negative,Neutral,Positive}`)
- Organized into `training/CreateML_Dataset/Train/` and `Test/` subdirectories
- **All training was done exclusively in Apple Create ML** (sound classifier task) → exported as `DogArousalValence.mlmodel`
- The Python scripts in `training/` (`extract_yamnet_embeddings.py`, `train_vocal_classifier.py`, `train_posture_classifier.py`, `export_yamnet_coreml.py`) were **not used for training** — they are exploratory/reference scripts only

---

## iOS App Architecture

### Data Flow
```
BLEManager
  → onAudioPacket(Data)  →  ClassifierCoordinator.handle(audioPacket:)
                               → AudioBuffer.append(packet:)
                                   → MuLawDecoder.decodeToFloat()
                                   → AVAudioPCMBuffer (16kHz, Float32, mono)
                                   → SNAudioStreamAnalyzer.analyze(_:atAudioFramePosition:)
                                       → GateObserver  (SNClassifySoundRequest .version1)
                                       → EmotionObserver (DogArousalValence model)
                                           [only logged if gate fired AND conf ≥ 0.4]
                               → waveform peak update (UI)
  → onIMUPacket(Data)    →  ClassifierCoordinator.handle(imuPacket:)
                               → IMUBuffer.append(packet:)
                                   → 50-sample window → 12-float MLMultiArray callback
```

### Key Thresholds (ClassifierCoordinator.swift)
- `GATE_THRESHOLD = 0.3` — minimum dog-class confidence to set `isDogDetected = true`
- `EMOTION_THRESHOLD = 0.4` — minimum emotion confidence to log an event

### Mood Derivation (OutlierDetector.swift)
Z-score ≥ 2.0σ above baseline triggers a flag per label:
- `High_Negative` elevated → **"Distressed"**
- `Low_Negative` elevated → **"Anxious"**
- `High_Positive` elevated → **"Excited / Playful"**
- All normal → **"Normal"**
- Requires ≥ 3 days of history before producing mood output.

### Persistence
- `UserDefaults["dog_sense_daily_log_v2"]` — 30-day rolling `[DayRecord]`
- Each `DayRecord`: `dateString: "yyyy-MM-dd"`, `counts: [String: Int]`

---

## Data Collection

```bash
cd data_collection
pip install -r requirements.txt
python collector.py --label bark --duration 30
```

Output: `data/<label>/session_NNN.wav` (16kHz mono int16) + `session_NNN.csv` (IMU columns).

---

## Build & Flash Firmware

```bash
# PlatformIO CLI
pio run -e nano33ble -t upload

# Or use PlatformIO IDE extension in VS Code
```

Dependencies (auto-resolved):
- `arduino-libraries/Arduino_BMI270_BMM150@^1.1.1`
- `arduino-libraries/ArduinoBLE@^1.3.7`

---

## Training Pipeline

All model training is done in **Apple Create ML** (not Python):

1. Prepare the dataset in `training/CreateML_Dataset/` with subdirectories named `{High,Medium,Low}_{Negative,Neutral,Positive}`
2. Open Create ML, create a new Sound Classifier project
3. Point Train/Test sources at the respective subdirectories
4. Train and evaluate in Create ML
5. Export → drag the `.mlmodel` into `ios_app/Moodle/Moodle/Resources/`

The Python scripts in `training/` are **not part of the active workflow** — they are exploratory reference scripts.

---

## Known Gaps / Future Work

- **PostureClassifier not wired into iOS UI** — `IMUBuffer` extracts features and fires `onWindowReady`, but no UI card or logging exists for posture state yet.
- **Info.plist BLE strings are empty** — `NSBluetoothAlwaysUsageDescription` needs a real user-facing string before App Store submission.
- **No reconnect logic** — `BLEManager` does not auto-reconnect if the peripheral drops.
- **Python training scripts are unused** — `training/*.py` are exploratory/reference only. Do not treat them as the ground truth for how the model was built. The sole training artifact is `DogArousalValence.mlmodel` produced by Create ML.
- **Waveform normalization** — currently normalizes to peak within the rolling 100-sample window; could be improved with RMS or a fixed scale.
- **Z-score std guard** — `OutlierDetector` skips labels where historical std < 0.5 (returns "normal"). Low-activity dogs may never trigger flags.

---

## Audio Codec Notes

µ-law (G.711) compresses int16 PCM to 8-bit, halving BLE bandwidth:
- Firmware encodes in `mulaw.h → encode_mulaw_buffer()`
- iOS decodes in `MuLawDecoder.swift` via 256-entry precomputed lookup table
- Both sides must agree on the same µ-law curve (CCITT standard, bias=132)

---

## Conventions

- Swift: `@Published` properties on main actor, heavy work on `analysisQueue` (`.userInitiated`)
- Arduino: ISR (`onPDMData`) only sets `audioReady` flag and writes to a double buffer; `loop()` sends
- Labels use `_` as separator (`High_Negative`), displayed by `.replacingOccurrences(of: "_", with: " ")`
- iOS minimum deployment target: iOS 16 (requires SoundAnalysis `SNClassifySoundRequest`)
