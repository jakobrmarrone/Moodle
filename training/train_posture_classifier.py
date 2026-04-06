"""
train_posture_classifier.py
----------------------------
Trains a Random Forest classifier on labeled IMU data (CSV files from collector.py)
to classify dog posture: alert / lying / sniffing / running.

Features are extracted from 50-sample (1 second) sliding windows with 25-sample stride.
Per-axis statistics (mean, std, L2 norm) give 12 features per window.

Usage:
  python train_posture_classifier.py --data-dir ../data_collection/data

Output:
  training/models/PostureClassifier.mlmodel
"""

import os
import sys
import argparse
import numpy as np
import pandas as pd
import coremltools as ct
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score, train_test_split
from sklearn.metrics import confusion_matrix, classification_report
from sklearn.preprocessing import LabelEncoder

POSTURE_LABELS = ["alert", "lying", "sniffing", "running"]
WINDOW_SAMPLES = 50    # 1 second at 50Hz
STRIDE_SAMPLES = 25    # 50% overlap
OUTPUT_DIR = "models"

FEATURE_NAMES = [
    "ax_mean", "ay_mean", "az_mean",
    "gx_mean", "gy_mean", "gz_mean",
    "ax_std",  "ay_std",  "az_std",
    "gx_std",  "gy_std",  "gz_std",
]


def extract_features_from_window(window: np.ndarray) -> np.ndarray:
    """
    window: (50, 6) array of [ax, ay, az, gx, gy, gz]
    Returns: (12,) feature vector [mean x6, std x6]
    """
    means = window.mean(axis=0)   # (6,)
    stds  = window.std(axis=0)    # (6,)
    return np.concatenate([means, stds])


def load_label_data(data_dir: str, label: str):
    """Load all CSVs for a label, extract sliding window features."""
    label_dir = os.path.join(data_dir, label)
    if not os.path.isdir(label_dir):
        return np.empty((0, 12))

    csv_files = sorted(f for f in os.listdir(label_dir) if f.endswith(".csv"))
    all_features = []

    for csv_name in csv_files:
        csv_path = os.path.join(label_dir, csv_name)
        df = pd.read_csv(csv_path)
        data = df[["ax_g", "ay_g", "az_g", "gx_dps", "gy_dps", "gz_dps"]].values

        # Sliding windows
        for start in range(0, len(data) - WINDOW_SAMPLES + 1, STRIDE_SAMPLES):
            window = data[start:start + WINDOW_SAMPLES]
            if len(window) == WINDOW_SAMPLES:
                feats = extract_features_from_window(window)
                all_features.append(feats)

    if not all_features:
        return np.empty((0, 12))
    return np.stack(all_features)


def main(data_dir: str):
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    X_all = []
    y_all = []

    for label in POSTURE_LABELS:
        features = load_label_data(data_dir, label)
        if len(features) == 0:
            print(f"WARNING: No CSV data found for label '{label}'. Skipping.")
            continue
        X_all.append(features)
        y_all.extend([label] * len(features))
        print(f"  {label}: {len(features)} windows from {data_dir}/{label}/")

    if not X_all:
        print("ERROR: No data found at all. Run collector.py first.")
        sys.exit(1)

    X = np.vstack(X_all)
    y = np.array(y_all)

    print(f"\nTotal windows: {len(X)}, features per window: {X.shape[1]}")

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    clf = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
    clf.fit(X_train, y_train)

    test_acc = clf.score(X_test, y_test)
    print(f"Test accuracy: {test_acc:.1%} (random chance = {1/len(POSTURE_LABELS):.0%})")

    y_pred = clf.predict(X_test)
    print("\nConfusion matrix (rows=true, cols=predicted):")
    print(confusion_matrix(y_test, y_pred, labels=POSTURE_LABELS))
    print("\nClassification report:")
    print(classification_report(y_test, y_pred, labels=POSTURE_LABELS))

    # Export to CoreML
    print("\nExporting to CoreML...")
    cml_model = ct.converters.sklearn.convert(
        clf,
        input_features=FEATURE_NAMES,
        output_feature_names="posture"
    )

    cml_model.short_description = "Dog posture classifier: alert / lying / sniffing / running"
    cml_model.input_description.update({name: "IMU window feature" for name in FEATURE_NAMES})
    cml_model.output_description["posture"] = "Predicted posture class"

    out_path = os.path.join(OUTPUT_DIR, "PostureClassifier.mlmodel")
    cml_model.save(out_path)
    print(f"PostureClassifier.mlmodel saved to {out_path}")

    # Quick verify
    sample = {name: float(X_test[0, i]) for i, name in enumerate(FEATURE_NAMES)}
    result = cml_model.predict(sample)
    print(f"Verify predict: input posture '{y_test[0]}' -> predicted '{result['posture']}'  OK")

    print(f"\nDone. Copy {out_path} into your Xcode project Resources group.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data-dir", default="../data_collection/data",
                        help="Root data directory containing label subdirectories")
    args = parser.parse_args()
    main(args.data_dir)
