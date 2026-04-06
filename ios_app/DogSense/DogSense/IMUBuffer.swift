import Foundation
import CoreML

/// Parses 12-byte BLE IMU packets and extracts features over 50-sample (1 sec) windows.
/// Feature vector (12 floats) matches what train_posture_classifier.py produces:
///   [ax_mean, ay_mean, az_mean, gx_mean, gy_mean, gz_mean,
///    ax_std,  ay_std,  az_std,  gx_std,  gy_std,  gz_std]
final class IMUBuffer {
    private let windowSize = 50    // 1 second at 50Hz
    private let slideSize  = 25    // 50% overlap

    // Each element: [ax, ay, az, gx, gy, gz]
    private var window: [[Float]] = []

    /// Called on the inference queue when a full window of features is ready.
    var onWindowReady: ((MLMultiArray) -> Void)?

    /// Parse one 12-byte BLE IMU packet.
    /// Format: 6 x big-endian int16 [ax*1000, ay*1000, az*1000, gx*10, gy*10, gz*10]
    func append(packet: Data) {
        guard packet.count == 12 else { return }

        let sample: [Float] = (0..<6).map { i -> Float in
            let raw = Int16(bitPattern: (UInt16(packet[i * 2]) << 8) | UInt16(packet[i * 2 + 1]))
            let scale: Float = i < 3 ? 1000.0 : 10.0
            return Float(raw) / scale
        }

        window.append(sample)

        if window.count >= windowSize {
            fireInference()
            window.removeFirst(slideSize)
        }
    }

    private func fireInference() {
        let n = windowSize
        var means = [Float](repeating: 0, count: 6)
        var stds  = [Float](repeating: 0, count: 6)

        for axis in 0..<6 {
            let vals = window.prefix(n).map { $0[axis] }
            let mean = vals.reduce(0, +) / Float(n)
            let variance = vals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(n)
            means[axis] = mean
            stds[axis]  = variance.squareRoot()
        }

        let features = means + stds  // 12 floats

        guard let mlArray = try? MLMultiArray(shape: [12], dataType: .double) else { return }
        for (i, v) in features.enumerated() {
            mlArray[i] = NSNumber(value: v)
        }
        onWindowReady?(mlArray)
    }
}
