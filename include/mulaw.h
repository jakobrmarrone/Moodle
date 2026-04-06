#pragma once
#include <stdint.h>

// ---------------------------------------------------------------------------
// G.711 µ-law (mu-law) encoder
// Encodes a 16-bit signed PCM sample to an 8-bit µ-law byte.
// This halves the audio data rate: 16kHz x 16-bit = 32KB/s -> 16KB/s.
// Decoding on the iPhone uses a 256-entry lookup table (MuLawDecoder.swift).
// ---------------------------------------------------------------------------

static inline uint8_t encode_mulaw(int16_t pcm) {
    const int MU = 255;
    const int BIAS = 0x84;  // 132

    // Take sign, then work on magnitude
    int sign = (pcm < 0) ? 0x80 : 0;
    if (pcm < 0) pcm = -pcm;

    // Clamp to 15-bit positive range
    if (pcm > 32767) pcm = 32767;

    // Add bias
    int sample = (int)pcm + BIAS;

    // Compress logarithmically (8 segments, 4-bit mantissa each)
    int exponent = 7;
    for (int expMask = 0x4000; (sample & expMask) == 0 && exponent > 0; expMask >>= 1) {
        exponent--;
    }
    int mantissa = (sample >> (exponent + 3)) & 0x0F;

    uint8_t encoded = (uint8_t)(~(sign | (exponent << 4) | mantissa));
    return encoded;
}

// ---------------------------------------------------------------------------
// Encode a buffer of int16_t PCM samples to uint8_t µ-law bytes in-place.
// src and dst may be the same pointer only if sizeof(dst) >= nSamples.
// Call with dst pointing to a buffer of at least nSamples bytes.
// ---------------------------------------------------------------------------
static inline void encode_mulaw_buffer(const int16_t* src, uint8_t* dst, int nSamples) {
    for (int i = 0; i < nSamples; i++) {
        dst[i] = encode_mulaw(src[i]);
    }
}
