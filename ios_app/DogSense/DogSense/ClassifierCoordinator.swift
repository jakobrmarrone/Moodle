import Foundation
import CoreML
import SoundAnalysis
import CoreMedia
import Combine

// Minimum confidence for the built-in gate to count as "dog detected"
private let GATE_THRESHOLD: Float = 0.3
// Minimum confidence for the emotion model result to be logged
private let EMOTION_THRESHOLD: Float = 0.4

/// Owns the audio and IMU buffers, wires up SNAudioStreamAnalyzer with a
/// two-stage approach:
///   Stage 1 — Apple's built-in sound classifier (gate): detects dog sounds
///   Stage 2 — DogArousalValence model: classifies emotional state
///             (only logged when gate is active)
final class ClassifierCoordinator: NSObject, ObservableObject {
    @Published var lastEmotionLabel   = "—"
    @Published var isDogDetected      = false

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

    override init() {
        super.init()
        setupAnalyzer()
    }

    // MARK: - Setup

    private func setupAnalyzer() {
        let analyzer = SNAudioStreamAnalyzer(format: audioBuffer.format)

        // Stage 1 — Built-in gate
        gateObserver = GateObserver { [weak self] isDog in
            self?.dogDetectedRecently = isDog
            DispatchQueue.main.async { self?.isDogDetected = isDog }
        }
        if let gateRequest = try? SNClassifySoundRequest(classifierIdentifier: .version1) {
            gateRequest.overlapFactor = 0.5
            try? analyzer.add(gateRequest, withObserver: gateObserver!)
        }

        // Stage 2 — Custom emotion model
        if let model = try? DogArousalValence(configuration: .init()).model,
           let emotionRequest = try? SNClassifySoundRequest(mlModel: model) {
            emotionRequest.overlapFactor = 0.5
            emotionObserver = EmotionObserver { [weak self] label, confidence in
                guard let self else { return }
                // Only log if the gate recently detected a dog sound
                guard self.dogDetectedRecently, confidence >= EMOTION_THRESHOLD else { return }
                DispatchQueue.main.async {
                    self.lastEmotionLabel = label
                    self.dailyLog.increment(label: label)
                    self.updateDetection()
                }
            }
            try? analyzer.add(emotionRequest, withObserver: emotionObserver!)
        }

        self.analyzer       = analyzer
        audioBuffer.analyzer = analyzer
    }

    // MARK: - BLE packet handlers (called from BLEManager callbacks)

    func handle(audioPacket data: Data) {
        analysisQueue.async { [weak self] in
            self?.audioBuffer.append(packet: data)
        }
    }

    func handle(imuPacket data: Data) {
        analysisQueue.async { [weak self] in
            self?.imuBuffer.append(packet: data)
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
    let onResult: (Bool) -> Void
    init(onResult: @escaping (Bool) -> Void) { self.onResult = onResult }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        // Check if any "dog" class has confidence above the gate threshold
        let dogConfidence = result.classifications
            .filter { $0.identifier.lowercased().contains("dog") }
            .map { Float($0.confidence) }
            .max() ?? 0
        onResult(dogConfidence >= GATE_THRESHOLD)
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
