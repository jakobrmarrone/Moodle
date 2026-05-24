import Foundation
import AVFoundation
import SoundAnalysis

/// Receives µ-law BLE audio packets, decodes them to float32 PCM,
/// and feeds each packet directly to the SNAudioStreamAnalyzer as a small
/// AVAudioPCMBuffer. The analyzer accumulates internally and handles its
/// own windowing — no need to pre-buffer on our side.
final class AudioBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: 16000,
                               channels: 1,
                               interleaved: false)!

    /// Set by ClassifierCoordinator after setup.
    var analyzer: SNAudioStreamAnalyzer?

    private var framePosition: AVAudioFramePosition = 0

    /// Call from ClassifierCoordinator on the analysis queue.
    func append(packet: Data) {
        let samples = MuLawDecoder.decodeToFloat(packet)   // [Float], 160 samples
        let frameCount = AVAudioFrameCount(samples.count)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Copy decoded float samples into the buffer's channel data
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }

        analyzer?.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(frameCount)
    }
}
