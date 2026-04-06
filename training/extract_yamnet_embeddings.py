"""
extract_yamnet_embeddings.py
-----------------------------
Loads all WAV files from data_collection/data/<label>/ directories,
runs each through YAMNet (from TF Hub) to extract 1024-dim embeddings,
and saves a single embeddings.npz file for use in train_vocal_classifier.py.

Usage:
  python extract_yamnet_embeddings.py --data-dir ../data_collection/data

Output:
  training/embeddings.npz  with keys: 'embeddings' (N, 1024) and 'labels' (N,)
  training/label_map.txt   with integer -> label name mapping
"""

import os
import sys
import argparse
import numpy as np
import soundfile as sf
import tensorflow as tf
import tensorflow_hub as hub

VOCAL_LABELS = ["bark", "whine", "growl"]
YAMNET_MODEL_URL = "https://tfhub.dev/google/yamnet/1"
SAMPLE_RATE = 16000
YAMNET_WINDOW = 15600  # 0.975s at 16kHz — minimum input length for YAMNet


def load_wav(path: str) -> np.ndarray:
    """Load a WAV file, zero-pad to YAMNET_WINDOW if needed, return float32 in [-1, 1].

    Short clips (< 0.975s) are padded with silence at the end. This matches
    what AudioBuffer.swift does on the iPhone before inference.
    """
    data, sr = sf.read(path, dtype='int16', always_2d=False)
    if sr != SAMPLE_RATE:
        raise ValueError(f"{path}: expected {SAMPLE_RATE}Hz, got {sr}Hz. "
                         "Re-record or resample before running this script.")
    samples = data.astype(np.float32) / 32768.0
    if len(samples) < YAMNET_WINDOW:
        samples = np.pad(samples, (0, YAMNET_WINDOW - len(samples)))
    return samples


def extract_embeddings(yamnet_model, waveform: np.ndarray) -> np.ndarray:
    """Run YAMNet and return mean-pooled 1024-dim embedding."""
    # YAMNet expects a 1-D float32 tensor
    waveform_tensor = tf.constant(waveform, dtype=tf.float32)
    _, embeddings, _ = yamnet_model(waveform_tensor)
    # embeddings shape: [N_frames, 1024] — mean-pool over time
    return embeddings.numpy().mean(axis=0)  # (1024,)


def main(data_dir: str, output_dir: str):
    print(f"[embeddings] Loading YAMNet from TF Hub (may download ~30MB on first run)...")
    yamnet_model = hub.load(YAMNET_MODEL_URL)
    print("[embeddings] YAMNet loaded.")

    all_embeddings = []
    all_labels = []

    for label_idx, label in enumerate(VOCAL_LABELS):
        label_dir = os.path.join(data_dir, label)
        if not os.path.isdir(label_dir):
            print(f"[embeddings] WARNING: No directory found for label '{label}' at {label_dir}")
            continue

        wav_files = sorted(f for f in os.listdir(label_dir) if f.endswith(".wav"))
        if not wav_files:
            print(f"[embeddings] WARNING: No WAV files found in {label_dir}")
            continue

        print(f"[embeddings] Processing {len(wav_files)} files for label '{label}'...")
        for wav_name in wav_files:
            wav_path = os.path.join(label_dir, wav_name)
            try:
                waveform = load_wav(wav_path)
            except Exception as e:
                print(f"[embeddings]   SKIP {wav_name}: {e}")
                continue

            embedding = extract_embeddings(yamnet_model, waveform)
            all_embeddings.append(embedding)
            all_labels.append(label_idx)
            print(f"[embeddings]   {wav_name} -> embedding shape {embedding.shape}")

    if not all_embeddings:
        print("[embeddings] ERROR: No embeddings extracted. Collect data first.")
        sys.exit(1)

    embeddings_arr = np.stack(all_embeddings)  # (N, 1024)
    labels_arr = np.array(all_labels, dtype=np.int32)

    out_path = os.path.join(output_dir, "embeddings.npz")
    np.savez(out_path, embeddings=embeddings_arr, labels=labels_arr)
    print(f"\n[embeddings] Saved {len(all_embeddings)} embeddings to {out_path}")
    print(f"  Shape: {embeddings_arr.shape}")
    for idx, name in enumerate(VOCAL_LABELS):
        count = int((labels_arr == idx).sum())
        print(f"  Class {idx} ({name}): {count} samples")

    # Save label map
    map_path = os.path.join(output_dir, "label_map.txt")
    with open(map_path, 'w') as f:
        for idx, name in enumerate(VOCAL_LABELS):
            f.write(f"{idx}\t{name}\n")
    print(f"[embeddings] Label map saved to {map_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir",
                        default="/Users/jakobmarrone/Downloads/Classes/BMED 456/dog_audio/labled_audio",
                        help="Root data directory containing label subdirectories")
    parser.add_argument("--output-dir", default=".",
                        help="Directory to write embeddings.npz (default: current dir)")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    main(args.data_dir, args.output_dir)
