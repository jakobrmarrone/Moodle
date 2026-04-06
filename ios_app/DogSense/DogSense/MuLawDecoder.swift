import Foundation

/// G.711 µ-law decode — 256-entry lookup table, mirrors the Python decode table in collector.py.
/// Called from AudioBuffer to convert raw BLE bytes back to int16 PCM.
enum MuLawDecoder {
    static let table: [Int16] = {
        var t = [Int16](repeating: 0, count: 256)
        for i in 0..<256 {
            let b = (~i) & 0xFF
            let sign: Int16 = (b & 0x80) != 0 ? -1 : 1
            let exponent = (b >> 4) & 0x07
            let mantissa = b & 0x0F
            let magnitude = ((mantissa << 3) + 0x84) << exponent
            t[i] = sign &* Int16(clamping: magnitude - 0x84)
        }
        return t
    }()

    /// Decode a single µ-law byte to a signed 16-bit PCM sample.
    static func decode(_ byte: UInt8) -> Int16 {
        table[Int(byte)]
    }

    /// Decode a buffer of µ-law bytes to float32 samples in [-1, 1].
    static func decodeToFloat(_ bytes: Data) -> [Float] {
        bytes.map { Float(table[Int($0)]) / 32768.0 }
    }
}
