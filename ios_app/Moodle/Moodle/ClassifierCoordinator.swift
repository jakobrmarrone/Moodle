import Foundation
import CoreML
import SoundAnalysis
import CoreMedia
import Combine

// Minimum confidence for the built-in gate to count as "dog detected"
private let GATE_THRESHOLD: Float = 0.3
// Minimum confidence for the emotion model result to be logged
private let EMOTION_THRESHOLD: Float = 0.4

/// A single classification result with label and confidence.
struct SoundClassification: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    var isDog: Bool { label.lowercased().contains("dog") }
}

/// Owns the audio and IMU buffers, wires up SNAudioStreamAnalyzer with a
/// two-stage approach:
///   Level 1 — Apple's built-in sound classifier (gate): detects dog sounds
///   Level 2 — DogArousalValence model: classifies emotional state
///             (only logged when gate is active)
final class ClassifierCoordinator: NSObject, ObservableObject {
    // Level 1 — General sound classification
    @Published var isDogDetected      = false
    @Published var gateClassifications: [SoundClassification] = []
    @Published var gateConfidence: Float = 0

    // Level 2 — Dog emotion classification
    @Published var lastEmotionLabel      = "—"
    @Published var lastEmotionConfidence: Float = 0

    // IMU — head orientation and activity
    @Published var latestOrientation: IMUOrientation?

    /// Raw axis rolling buffers updated at the full 50 Hz IMU rate for smooth charts.
    struct LiveIMURaw {
        var ax: [Float] = []; var ay: [Float] = []; var az: [Float] = []
        var gx: [Float] = []; var gy: [Float] = []; var gz: [Float] = []
    }
    @Published var liveIMURaw = LiveIMURaw()

    /// Rolling audio waveform samples for the UI (downsampled to ~100 points).
    @Published var audioWaveform: [Float] = []
    private let waveformLength = 100

    let dailyLog        = DailyLog()
    let outlierDetector = OutlierDetector()
    @Published var detectionResult: OutlierDetector.DetectionResult?

    private let audioBuffer   = AudioBuffer()
    let imuBuffer             = IMUBuffer()

    private var analyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.dogsense.analysis", qos: .userInitiated)

    // Keep observers alive (SNAudioStreamAnalyzer holds weak refs)
    private var gateObserver:    GateObserver?
    private var emotionObserver: EmotionObserver?

    private var dogDetectedRecently = false

    convenience override init() {
        self.init(forPreview: false)
    }

    init(forPreview: Bool) {
        super.init()
        if !forPreview {
            setupAnalyzer()
            setupIMU()
        }
    }

    // MARK: - Setup

    private func setupAnalyzer() {
        let analyzer = SNAudioStreamAnalyzer(format: audioBuffer.format)

        // Level 1 — Built-in gate
        gateObserver = GateObserver { [weak self] isDog, topClassifications, dogConf in
            self?.dogDetectedRecently = isDog
            DispatchQueue.main.async {
                self?.isDogDetected = isDog
                self?.gateClassifications = topClassifications
                self?.gateConfidence = dogConf
            }
        }
        if let gateRequest = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            gateRequest.overlapFactor = 0.5
            try? analyzer.add(gateRequest, withObserver: gateObserver!)
        }

        // Level 2 — Custom emotion model
        if let model = try? DogArousalValence(configuration: .init()).model,
           let emotionRequest = try? SNClassifySoundRequest(mlModel: model) {
            emotionRequest.overlapFactor = 0.5
            emotionObserver = EmotionObserver { [weak self] label, confidence in
                guard let self else { return }
                guard self.dogDetectedRecently, confidence >= EMOTION_THRESHOLD else { return }
                DispatchQueue.main.async {
                    self.lastEmotionLabel = label
                    self.lastEmotionConfidence = confidence
                    self.dailyLog.increment(label: label)
                    self.updateDetection()
                }
            }
            try? analyzer.add(emotionRequest, withObserver: emotionObserver!)
        }

        self.analyzer       = analyzer
        audioBuffer.analyzer = analyzer
    }

    private func setupIMU() {
        imuBuffer.onSampleReady = { [weak self] ax, ay, az, gx, gy, gz in
            guard let self else { return }
            DispatchQueue.main.async {
                let cap = 100
                var r = self.liveIMURaw
                r.ax.append(ax); if r.ax.count > cap { r.ax.removeFirst() }
                r.ay.append(ay); if r.ay.count > cap { r.ay.removeFirst() }
                r.az.append(az); if r.az.count > cap { r.az.removeFirst() }
                r.gx.append(gx); if r.gx.count > cap { r.gx.removeFirst() }
                r.gy.append(gy); if r.gy.count > cap { r.gy.removeFirst() }
                r.gz.append(gz); if r.gz.count > cap { r.gz.removeFirst() }
                self.liveIMURaw = r
            }
        }

        imuBuffer.onWindowReady = { [weak self] orientation in
            guard let self else { return }
            DispatchQueue.main.async {
                self.latestOrientation = orientation
                // Log one entry per activity bout, not per window.
                // isNewBout is true only on the first window where a new
                // committedLabel takes effect (after its minimum sustained duration).
                if orientation.isNewBout && orientation.committedLabel != .unknown {
                    self.dailyLog.increment(label: orientation.committedLabel.rawValue)
                }
                self.updateDetection()
            }
        }
    }

    // MARK: - BLE packet handlers

    func handle(audioPacket data: Data) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.audioBuffer.append(packet: data)

            let samples = MuLawDecoder.decodeToFloat(data)
            let peak = samples.map { abs($0) }.max() ?? 0
            DispatchQueue.main.async {
                self.audioWaveform.append(peak)
                if self.audioWaveform.count > self.waveformLength {
                    self.audioWaveform.removeFirst(self.audioWaveform.count - self.waveformLength)
                }
            }
        }
    }

    func handle(imuPacket data: Data) {
        analysisQueue.async { [weak self] in
            self?.imuBuffer.append(packet: data)
        }
    }

    /// Call when BLE connects to restart IMU calibration.
    func resetIMUCalibration() {
        analysisQueue.async { [weak self] in
            self?.imuBuffer.reset()
        }
    }

    // MARK: - Outlier detection

    private func updateDetection() {
        let today    = dailyLog.today
        let todayKey = DayRecord.dateString(for: Date())
        let history  = dailyLog.records.filter { $0.dateString != todayKey }
        detectionResult = outlierDetector.analyze(today: today, history: history)
    }
}

// MARK: - SNResultsObserving wrappers (private)

private final class GateObserver: NSObject, SNResultsObserving {
    let onResult: (Bool, [SoundClassification], Float) -> Void
    init(onResult: @escaping (Bool, [SoundClassification], Float) -> Void) { self.onResult = onResult }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }

        let top = result.classifications.prefix(5).map {
            SoundClassification(label: $0.identifier, confidence: Float($0.confidence))
        }

        let dogConfidence = result.classifications
            .filter { $0.identifier.lowercased().contains("dog") }
            .map { Float($0.confidence) }
            .max() ?? 0
        onResult(dogConfidence >= GATE_THRESHOLD, top, dogConfidence)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("[Gate] Error: \(error)")
    }
}

private final class EmotionObserver: NSObject, SNResultsObserving {
    let onResult: (String, Float) -> Void
    init(onResult: @escaping (String, Float) -> Void) { self.onResult = onResult }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let top = result.classifications.first else { return }
        onResult(top.identifier, Float(top.confidence))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        print("[Emotion] Error: \(error)")
    }
}
