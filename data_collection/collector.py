"""
DogSense Data Collector
-----------------------
Connects to the Arduino Nano 33 BLE Sense over BLE, receives audio and IMU
streams, and saves labeled data to disk:
  - Audio -> data/<label>/session_NNN.wav  (16kHz mono int16 PCM)
  - IMU   -> data/<label>/session_NNN.csv  (columns: ax_g, ay_g, az_g, gx_dps, gy_dps, gz_dps)

Usage:
  python collector.py --label bark --duration 30
  python collector.py --label whine --duration 30
  python collector.py --label growl --duration 30
  python collector.py --label alert --duration 60
  python collector.py --label lying --duration 60
  python collector.py --label sniffing --duration 60
  python collector.py --label running --duration 60

Prerequisites:
  pip install -r requirements.txt
"""

import asyncio
import argparse
import os
import struct
import signal
import sys
import time
import numpy as np
import soundfile as sf
from bleak import BleakClient, BleakScanner

# ---------------------------------------------------------------------------
# UUIDs (must match ble_config.h)
# ---------------------------------------------------------------------------
SERVICE_UUID  = "8d8439b3-ecbc-59a6-8135-1b1cb5623943"
AUDIO_UUID    = "6aefa1e2-d6b9-5cb9-9fcb-4447897212f2"
IMU_UUID      = "66c1f950-3f93-5424-87a2-cfef024bd248"
COMMAND_UUID  = "a5568574-2b7e-578f-b456-a6a54fb175d2"

DEVICE_NAME   = "DogSense"
SAMPLE_RATE   = 16000

# ---------------------------------------------------------------------------
# G.711 µ-law decode table (256 entries, mirrors MuLawDecoder.swift)
# ---------------------------------------------------------------------------
def _build_mulaw_decode_table():
    table = np.zeros(256, dtype=np.int16)
    for i in range(256):
        b = ~i & 0xFF
        sign = -1 if (b & 0x80) else 1
        exponent = (b >> 4) & 0x07
        mantissa = b & 0x0F
        magnitude = ((mantissa << 3) + 0x84) << exponent
        table[i] = np.int16(sign * (magnitude - 0x84))
    return table

MULAW_DECODE = _build_mulaw_decode_table()


def decode_mulaw(data: bytes) -> np.ndarray:
    """Decode a bytes object of µ-law samples to int16 numpy array."""
    indices = np.frombuffer(data, dtype=np.uint8)
    return MULAW_DECODE[indices]


# ---------------------------------------------------------------------------
# Session state (shared between async callbacks and main coroutine)
# ---------------------------------------------------------------------------
class Session:
    def __init__(self, wav_path: str, csv_path: str):
        self.wav_file = sf.SoundFile(wav_path, mode='w', samplerate=SAMPLE_RATE,
                                     channels=1, subtype='PCM_16')
        self.csv_rows = []
        self.audio_packets = 0
        self.imu_packets = 0
        self.start_time = time.time()
        self._stop = False

    def write_audio(self, data: bytes):
        pcm = decode_mulaw(data)
        self.wav_file.write(pcm)
        self.audio_packets += 1

    def write_imu(self, data: bytes):
        # 6 big-endian int16 values
        vals = struct.unpack('>6h', data)
        ax = vals[0] / 1000.0
        ay = vals[1] / 1000.0
        az = vals[2] / 1000.0
        gx = vals[3] / 10.0
        gy = vals[4] / 10.0
        gz = vals[5] / 10.0
        self.csv_rows.append((ax, ay, az, gx, gy, gz))
        self.imu_packets += 1

    def flush_and_close(self):
        self.wav_file.close()
        return self.csv_rows

    @property
    def elapsed(self):
        return time.time() - self.start_time


# ---------------------------------------------------------------------------
# Find next available session number for a label
# ---------------------------------------------------------------------------
def next_session_number(output_dir: str, label: str) -> int:
    label_dir = os.path.join(output_dir, label)
    os.makedirs(label_dir, exist_ok=True)
    n = 1
    while os.path.exists(os.path.join(label_dir, f"session_{n:03d}.wav")):
        n += 1
    return n


# ---------------------------------------------------------------------------
# Main async collection loop
# ---------------------------------------------------------------------------
async def collect(label: str, duration: float, output_dir: str):
    print(f"[collector] Scanning for '{DEVICE_NAME}'...")
    device = await BleakScanner.find_device_by_name(DEVICE_NAME, timeout=15.0)
    if device is None:
        print(f"[collector] ERROR: '{DEVICE_NAME}' not found. Is the board powered and advertising?")
        sys.exit(1)

    print(f"[collector] Found {device.name} ({device.address})")

    n = next_session_number(output_dir, label)
    label_dir = os.path.join(output_dir, label)
    wav_path = os.path.join(label_dir, f"session_{n:03d}.wav")
    csv_path = os.path.join(label_dir, f"session_{n:03d}.csv")

    session = Session(wav_path, csv_path)
    stop_event = asyncio.Event()

    def on_audio(_, data: bytearray):
        session.write_audio(bytes(data))

    def on_imu(_, data: bytearray):
        session.write_imu(bytes(data))

    # Handle Ctrl-C gracefully
    def handle_sigint(*_):
        print("\n[collector] Stopping early...")
        stop_event.set()

    signal.signal(signal.SIGINT, handle_sigint)

    async with BleakClient(device) as client:
        print(f"[collector] Connected. Starting stream for {duration}s...")

        await client.start_notify(AUDIO_UUID, on_audio)
        await client.start_notify(IMU_UUID, on_imu)

        # Tell firmware to start streaming
        await client.write_gatt_char(COMMAND_UUID, bytes([0x01]), response=False)

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=duration)
        except asyncio.TimeoutError:
            pass  # Duration elapsed normally

        # Stop streaming
        await client.write_gatt_char(COMMAND_UUID, bytes([0x00]), response=False)
        await client.stop_notify(AUDIO_UUID)
        await client.stop_notify(IMU_UUID)

    # Flush and save
    csv_rows = session.flush_and_close()
    elapsed = session.elapsed

    # Write CSV
    with open(csv_path, 'w') as f:
        f.write("ax_g,ay_g,az_g,gx_dps,gy_dps,gz_dps\n")
        for row in csv_rows:
            f.write(",".join(f"{v:.4f}" for v in row) + "\n")

    print(f"\n[collector] Done.")
    print(f"  Label:         {label}")
    print(f"  Duration:      {elapsed:.1f}s")
    print(f"  Audio packets: {session.audio_packets} ({session.audio_packets * 160 / SAMPLE_RATE:.1f}s of audio)")
    print(f"  IMU packets:   {session.imu_packets} ({session.imu_packets / 50.0:.1f}s at 50Hz)")
    print(f"  WAV saved to:  {wav_path}")
    print(f"  CSV saved to:  {csv_path}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DogSense BLE data collector")
    parser.add_argument("--label", required=True,
                        choices=["bark", "whine", "growl",
                                 "alert", "lying", "sniffing", "running"],
                        help="Behavior label for this recording session")
    parser.add_argument("--duration", type=float, default=30.0,
                        help="Recording duration in seconds (default: 30)")
    parser.add_argument("--output-dir", default="data",
                        help="Root directory for saved data (default: ./data)")
    args = parser.parse_args()

    asyncio.run(collect(args.label, args.duration, args.output_dir))
