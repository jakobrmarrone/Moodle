"""
train_vocal_classifier.py
--------------------------
Trains a small Keras classification head on top of YAMNet embeddings
to classify dog vocalizations: bark / whine / growl.

YAMNet weights are NOT touched — this is pure transfer learning on the
frozen embedding outputs produced by extract_yamnet_embeddings.py.

Usage:
  python train_vocal_classifier.py

Output:
  training/vocal_classifier_head/  (saved Keras model)
"""

import os
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split
from sklearn.metrics import confusion_matrix, classification_report

VOCAL_LABELS = ["bark", "whine", "growl"]
EMBEDDINGS_PATH = "embeddings.npz"
OUTPUT_DIR = "vocal_classifier_head"
EPOCHS = 30
BATCH_SIZE = 16
RANDOM_SEED = 42


def build_head(n_classes: int) -> keras.Model:
    model = keras.Sequential([
        keras.layers.Dense(64, activation='relu', input_shape=(1024,)),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(n_classes, activation='softmax'),
    ], name="dog_vocal_head")
    return model


def main():
    if not os.path.exists(EMBEDDINGS_PATH):
        print(f"ERROR: {EMBEDDINGS_PATH} not found. Run extract_yamnet_embeddings.py first.")
        return

    data = np.load(EMBEDDINGS_PATH)
    X = data['embeddings'].astype(np.float32)  # (N, 1024)
    y = data['labels'].astype(np.int32)         # (N,)

    n_classes = len(VOCAL_LABELS)
    print(f"Loaded {len(X)} samples, {n_classes} classes")
    for i, name in enumerate(VOCAL_LABELS):
        print(f"  {name}: {(y == i).sum()} samples")

    if len(X) < 10:
        print("ERROR: Too few samples to train. Collect more data.")
        return

    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_SEED, stratify=y
    )
    print(f"\nTrain: {len(X_train)}  Val: {len(X_val)}")

    y_train_cat = keras.utils.to_categorical(y_train, n_classes)
    y_val_cat   = keras.utils.to_categorical(y_val, n_classes)

    model = build_head(n_classes)
    model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )
    model.summary()

    callbacks = [
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
    ]

    history = model.fit(
        X_train, y_train_cat,
        validation_data=(X_val, y_val_cat),
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        callbacks=callbacks,
        verbose=1,
    )

    val_loss, val_acc = model.evaluate(X_val, y_val_cat, verbose=0)
    print(f"\nValidation accuracy: {val_acc:.1%}")

    y_pred = model.predict(X_val, verbose=0).argmax(axis=1)
    print("\nConfusion matrix (rows=true, cols=predicted):")
    print(confusion_matrix(y_val, y_pred))
    print("\nClassification report:")
    print(classification_report(y_val, y_pred, target_names=VOCAL_LABELS))

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    model.save(OUTPUT_DIR)
    print(f"\nModel saved to {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
