"""
export_yamnet_coreml.py
------------------------
Exports a CoreML model for dog vocal classification.

Strategy:
  1. Try combined: wrap YAMNet + head in a tf.Module, save as SavedModel,
     convert to CoreML. One model, waveform in -> label out.
  2. Fallback: save just the Keras head as SavedModel, convert to CoreML.
     Input is 1024-dim embeddings (YAMNet runs separately or in Swift).

Usage:
  python export_yamnet_coreml.py

Output:
  training/models/DogVocalClassifier.mlpackage  (combined, preferred)
  OR
  training/models/DogVocalClassifier_head.mlpackage  (head-only fallback)
"""

import os, sys, shutil
import numpy as np
import tensorflow as tf
import tensorflow_hub as hub
import coremltools as ct

YAMNET_MODEL_URL = "https://tfhub.dev/google/yamnet/1"
HEAD_MODEL_DIR   = "vocal_classifier_head"
OUTPUT_DIR       = "models"
VOCAL_LABELS     = ["bark", "whine", "growl"]
WAVEFORM_LENGTH  = 15600


# ---------------------------------------------------------------------------
# Combined export: YAMNet + head as one SavedModel -> CoreML
# ---------------------------------------------------------------------------

class AudioClassifier(tf.Module):
    """Wraps YAMNet + classification head with a clean serving signature."""
    def __init__(self, yamnet, head):
        super().__init__()
        self._yamnet = yamnet
        self._head = head

    @tf.function(input_signature=[
        tf.TensorSpec(shape=[WAVEFORM_LENGTH], dtype=tf.float32, name="waveform")
    ])
    def classify(self, waveform):
        _, embeddings, _ = self._yamnet(waveform)
        mean_emb = tf.reduce_mean(embeddings, axis=0, keepdims=True)  # [1, 1024]
        return self._head(mean_emb, training=False)[0]                 # [3]


def export_combined(yamnet, head) -> str:
    savedmodel_path = "combined_savedmodel"
    if os.path.exists(savedmodel_path):
        shutil.rmtree(savedmodel_path)

    print("[export] Saving combined YAMNet+head as SavedModel...")
    classifier = AudioClassifier(yamnet, head)
    tf.saved_model.save(
        classifier,
        savedmodel_path,
        signatures={"serving_default": classifier.classify}
    )

    print("[export] Converting combined SavedModel to CoreML...")
    mlmodel = ct.convert(
        savedmodel_path,
        source="tensorflow",
        inputs=[ct.TensorType(name="waveform", shape=(WAVEFORM_LENGTH,), dtype=np.float32)],
        minimum_deployment_target=ct.target.iOS16,
        classifier_config=ct.ClassifierConfig(VOCAL_LABELS),
    )

    mlmodel.short_description = "Dog vocal classifier: bark/whine/growl (YAMNet + head)"
    mlmodel.input_description["waveform"] = "16kHz mono audio, 15600 float32 samples in [-1,1]"

    out_path = os.path.join(OUTPUT_DIR, "DogVocalClassifier.mlpackage")
    mlmodel.save(out_path)
    print(f"[export] Saved -> {out_path}")
    return out_path


# ---------------------------------------------------------------------------
# Head-only fallback: just the Dense classification head
# ---------------------------------------------------------------------------

def export_head_only(head) -> str:
    savedmodel_path = "head_savedmodel"
    if os.path.exists(savedmodel_path):
        shutil.rmtree(savedmodel_path)

    print("[export] Saving classification head as SavedModel...")
    head.save(savedmodel_path)

    print("[export] Converting head SavedModel to CoreML...")
    mlmodel = ct.convert(
        savedmodel_path,
        source="tensorflow",
        minimum_deployment_target=ct.target.iOS16,
        classifier_config=ct.ClassifierConfig(VOCAL_LABELS),
    )

    mlmodel.short_description = "Dog vocal head: bark/whine/growl (input: 1024-dim YAMNet embedding)"

    out_path = os.path.join(OUTPUT_DIR, "DogVocalClassifier_head.mlpackage")
    mlmodel.save(out_path)
    print(f"[export] Saved -> {out_path}")
    print("[export] NOTE: head-only model needs YAMNet embedding preprocessing in Swift.")
    return out_path


# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

def verify(model_path: str, is_combined: bool):
    print(f"[export] Verifying {os.path.basename(model_path)}...")
    m = ct.models.MLModel(model_path)
    if is_combined:
        dummy = {"waveform": np.zeros(WAVEFORM_LENGTH, dtype=np.float32)}
    else:
        dummy = {"dense_input": np.zeros((1, 1024), dtype=np.float32)}
    out = m.predict(dummy)
    print(f"[export]   Output keys: {list(out.keys())}  OK")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("[export] Loading YAMNet from TF Hub...")
    yamnet = hub.load(YAMNET_MODEL_URL)

    if not os.path.exists(HEAD_MODEL_DIR):
        print(f"ERROR: {HEAD_MODEL_DIR} not found. Run train_vocal_classifier.py first.")
        sys.exit(1)

    print(f"[export] Loading Keras head from {HEAD_MODEL_DIR}...")
    head = tf.keras.models.load_model(HEAD_MODEL_DIR)

    # Try combined first
    try:
        out_path = export_combined(yamnet, head)
        verify(out_path, is_combined=True)
        print(f"\n[export] SUCCESS. Drag into Xcode Resources:\n  {out_path}")
    except Exception as e:
        print(f"\n[export] Combined export failed ({type(e).__name__}: {e})")
        print("[export] Trying head-only fallback...")
        try:
            out_path = export_head_only(head)
            verify(out_path, is_combined=False)
            print(f"\n[export] SUCCESS (head only). Drag into Xcode Resources:\n  {out_path}")
        except Exception as e2:
            print(f"\n[export] Head-only also failed: {e2}")
            print("[export] Both approaches failed. Try: pip install coremltools==8.0")


if __name__ == "__main__":
    main()
