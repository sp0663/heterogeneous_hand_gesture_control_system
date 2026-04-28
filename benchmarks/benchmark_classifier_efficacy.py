"""
Feeds a standardised static dataset of spatial landmark coordinates into
BOTH classifier pipelines and computes:
  - Confusion matrix
  - Per-class Precision, Recall, F1-Score
  - Macro-averaged and weighted-averaged metrics
  - Overall accuracy

The four gesture classes evaluated (shared by both pipelines):
  fist | open_palm | index_finger | pinch

MODES
-----
  --mode software     : run software classifier only (no hardware needed)
  --mode hardware     : run FPGA classifier only (requires --port)
  --mode both         : run both and produce a side-by-side comparison

SOFTWARE CLASSIFIER
-------------------
  Uses GestureRecogniser from gesture_media_controller.
  A fresh instance is created per sample to avoid state carry-over.

FPGA CLASSIFIER
---------------
  Serialises each sample via build_frame_bytes() and sends over UART.
  Receives 1-byte ACK from the FPGA containing gesture_id[2:0].
  Falls back to SOFTWARE FPGA REPLICA if --port is omitted.

SOFTWARE FPGA REPLICA
---------------------
  A pure-Python reimplementation of gesture_classifier.v logic
  (dist-based pinch, angle-based finger extension, fist/open/index rules).
  Activated automatically when --port is not supplied in hardware/both mode.

Usage
-----
    python benchmark_classifier_efficacy.py --mode software
    python benchmark_classifier_efficacy.py --mode hardware --port /dev/ttyUSB1
    python benchmark_classifier_efficacy.py --mode both     --port /dev/ttyUSB1
    python benchmark_classifier_efficacy.py --mode both     # uses FPGA replica
"""

import argparse
import csv
import json
import math
import os
import sys
import time
from collections import defaultdict
from datetime import datetime

import numpy as np

_REPO_ROOT  = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_HOMO_DIR   = os.path.join(_REPO_ROOT, "gesture_media_controller")
_HETERO_DIR = os.path.join(_REPO_ROOT, "heterogeneous_hand_gesture_control_system", "app")
sys.path.insert(0, _HOMO_DIR)
sys.path.insert(0, _HETERO_DIR)

RESULTS_DIR  = os.path.join(os.path.dirname(__file__), "results")
DATASET_PATH = os.path.join(os.path.dirname(__file__), "data", "static_gesture_dataset.json")

FPGA_ID_TO_LABEL = {0:"pinch", 1:"fist", 2:"open_palm",
                    3:"index_finger", 4:"unknown", 5:"pinch_cw", 6:"pinch_acw"}
CLASSES = ["fist", "open_palm", "index_finger", "pinch"]


#  Software FPGA Replica
#  Mirrors gesture_classifier.v + feature_extractor.v logic in Python

def _sq_dist_norm(lm_norm, id1, id2):
    """Squared Euclidean distance between two normalised landmarks."""
    a = lm_norm[id1]
    b = lm_norm[id2]
    return (a["nx"] - b["nx"]) ** 2 + (a["ny"] - b["ny"]) ** 2


def _vec_angle_norm(lm_norm, id1, id2, id3):
    """
    Angle at landmark id2 between vectors id1→id2 and id3→id2.
    Mirrors angle_calculator.v logic (cos-rule in integer space).
    Returns degrees.
    """
    p1 = np.array([lm_norm[id1]["nx"], lm_norm[id1]["ny"]], dtype=float)
    p2 = np.array([lm_norm[id2]["nx"], lm_norm[id2]["ny"]], dtype=float)
    p3 = np.array([lm_norm[id3]["nx"], lm_norm[id3]["ny"]], dtype=float)
    v1 = p1 - p2
    v2 = p3 - p2
    n1, n2 = np.linalg.norm(v1), np.linalg.norm(v2)
    if n1 < 1e-6 or n2 < 1e-6:
        return 0.0
    cos = np.clip(np.dot(v1, v2) / (n1 * n2), -1.0, 1.0)
    return float(np.degrees(np.arccos(cos)))


def fpga_replica_classify(lm_norm: list) -> str:
    """
    Software replica of gesture_classifier.v (static gestures only).
    lm_norm: list of 21 dicts {id, nx, ny}  (normalised uint16 coords).
    Returns gesture label string.
    """
    lm = {d["id"]: d for d in lm_norm}  # id-indexed dict

    #  Pinch check (mirrors is_pinch wire in gesture_classifier.v) 
    dist_ti  = _sq_dist_norm(lm, 4, 8)   # thumb_tip ↔ index_tip
    dist_wm  = _sq_dist_norm(lm, 0, 12)  # wrist     ↔ middle_tip
    is_pinch = (dist_ti * 16) < dist_wm

    if is_pinch:
        return "pinch"

    #  Finger extension (mirrors angle_calculator.v, threshold 160°) 
    # Thumb: joints 2→3→4
    thumb_ext   = _vec_angle_norm(lm, 2, 3, 4)   > 160
    # Index:  joints 5→6→7
    index_ext   = _vec_angle_norm(lm, 5, 6, 7)   > 160
    # Middle: joints 9→10→11
    middle_ext  = _vec_angle_norm(lm, 9, 10, 11) > 160
    # Ring:   joints 13→14→15
    ring_ext    = _vec_angle_norm(lm, 13, 14, 15) > 160
    # Pinky:  joints 17→18→19
    pinky_ext   = _vec_angle_norm(lm, 17, 18, 19) > 160

    #  Gesture rules (mirrors gesture_classifier.v always block) 
    if not index_ext and not middle_ext and not ring_ext and not pinky_ext:
        return "fist"
    if thumb_ext and index_ext and middle_ext and ring_ext and pinky_ext:
        return "open_palm"
    if index_ext and not middle_ext and not ring_ext and not pinky_ext:
        return "index_finger"
    return "unknown"


#  Software classifier (GestureRecogniser)

def software_classify(sample: dict) -> tuple:
    """
    Run one sample through GestureRecogniser.
    Returns (predicted_label, latency_ms).

    GestureRecogniser is stateful: pinch detection requires prev_angle to be
    set from a prior frame (first call always returns 'unknown' for pinch).
    Fist-move detection requires prev_fist_y. To mirror live-pipeline
    behaviour, we prime the recognizer with one silent call, then time
    the second call which produces the stable prediction.
    """
    from gesture_recogniser import GestureRecogniser
    recon = GestureRecogniser()   # fresh instance per sample
    lm    = sample["landmarks_px"]

    # Priming call: populates prev_angle, prev_fist_y, swipe_history[0].
    # Not timed – mirrors the recognizer receiving the previous frame.
    recon.recognise_gesture(lm, "Right", None)

    # Timed classification call with the same landmarks.
    # Same-position second call: delta ≈ 0 → pinch returns 'pinch' (static).
    t0 = time.perf_counter()
    pred = recon.recognise_gesture(lm, "Right", None)
    t1 = time.perf_counter()
    latency = (t1 - t0) * 1e3

    # Normalise label to match FPGA namespace
    label_map = {
        "fist":                "fist",
        "open_palm":           "open_palm",
        "index_pointing":      "index_finger",
        "pinch":               "pinch",
        "pinch_clockwise":     "pinch_cw",
        "pinch_anticlockwise": "pinch_acw",
        "unknown":             "unknown",
    }
    pred_norm = label_map.get(pred, pred)
    return pred_norm, latency


#  FPGA / replica classifier

def fpga_classify_serial(sample: dict, ser) -> tuple:
    """
    Send 105-byte UART frame, receive 1-byte ACK.
    Returns (predicted_label, latency_ms).
    """
    payload = bytearray(sample["uart_frame_bytes"])
    ser.reset_input_buffer()
    t0 = time.perf_counter()
    ser.write(payload)
    ser.flush()
    ack = ser.read(1)
    t1 = time.perf_counter()
    latency = (t1 - t0) * 1e3
    if len(ack) != 1:
        return "timeout", latency
    gid  = ack[0] & 0x07
    return FPGA_ID_TO_LABEL.get(gid, f"id={gid}"), latency


def fpga_classify_replica(sample: dict) -> tuple:
    """Use software FPGA replica. Returns (predicted_label, latency_ms)."""
    t0   = time.perf_counter()
    pred = fpga_replica_classify(sample["landmarks_norm"])
    t1   = time.perf_counter()
    return pred, (t1 - t0) * 1e3


#  Metrics

def confusion_matrix(y_true: list, y_pred: list, classes: list) -> np.ndarray:
    n   = len(classes)
    idx = {c: i for i, c in enumerate(classes)}
    cm  = np.zeros((n, n), dtype=int)
    for t, p in zip(y_true, y_pred):
        ti = idx.get(t, -1)
        pi = idx.get(p, -1)
        if ti >= 0 and pi >= 0:
            cm[ti][pi] += 1
    return cm


def class_metrics(cm: np.ndarray, classes: list) -> dict:
    metrics = {}
    for i, cls in enumerate(classes):
        tp = cm[i, i]
        fp = cm[:, i].sum() - tp
        fn = cm[i, :].sum() - tp
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall    = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1        = (2 * precision * recall / (precision + recall)
                     if (precision + recall) > 0 else 0.0)
        metrics[cls] = {
            "tp": int(tp), "fp": int(fp), "fn": int(fn),
            "precision": round(precision, 4),
            "recall":    round(recall,    4),
            "f1_score":  round(f1,        4),
        }
    total = cm.sum()
    accuracy = float(np.trace(cm)) / total if total > 0 else 0.0

    # Macro average
    p_vals = [metrics[c]["precision"] for c in classes]
    r_vals = [metrics[c]["recall"]    for c in classes]
    f_vals = [metrics[c]["f1_score"]  for c in classes]

    # Weighted average
    support = {c: int(cm[i, :].sum()) for i, c in enumerate(classes)}
    wt_p = sum(metrics[c]["precision"] * support[c] for c in classes) / total
    wt_r = sum(metrics[c]["recall"]    * support[c] for c in classes) / total
    wt_f = sum(metrics[c]["f1_score"]  * support[c] for c in classes) / total

    return {
        "per_class":         metrics,
        "accuracy":          round(accuracy, 4),
        "macro_precision":   round(sum(p_vals) / len(p_vals), 4),
        "macro_recall":      round(sum(r_vals) / len(r_vals), 4),
        "macro_f1":          round(sum(f_vals) / len(f_vals), 4),
        "weighted_precision":round(wt_p, 4),
        "weighted_recall":   round(wt_r, 4),
        "weighted_f1":       round(wt_f, 4),
        "support":           support,
    }


def print_confusion_matrix(cm: np.ndarray, classes: list, title: str):
    w = 14
    print(f"\n  {title}")
    print("  " + "-" * (w * (len(classes) + 1) + 2))
    header = f"  {'True / Pred':<{w}}" + "".join(f"{c:>{w}}" for c in classes)
    print(header)
    print("  " + "-" * (w * (len(classes) + 1) + 2))
    for i, cls in enumerate(classes):
        row = f"  {cls:<{w}}" + "".join(f"{cm[i,j]:>{w}}" for j in range(len(classes)))
        print(row)
    print("  " + "-" * (w * (len(classes) + 1) + 2))


def print_metrics(m: dict, title: str):
    print(f"\n  {title}")
    print(f"  {'Class':<16} {'Precision':>10} {'Recall':>10} {'F1-Score':>10} {'Support':>10}")
    print("  " + "-" * 58)
    for cls, v in m["per_class"].items():
        print(f"  {cls:<16} {v['precision']:>10.4f} {v['recall']:>10.4f} "
              f"{v['f1_score']:>10.4f} {m['support'][cls]:>10}")
    print("  " + "-" * 58)
    print(f"  {'Macro avg':<16} {m['macro_precision']:>10.4f} "
          f"{m['macro_recall']:>10.4f} {m['macro_f1']:>10.4f}")
    print(f"  {'Weighted avg':<16} {m['weighted_precision']:>10.4f} "
          f"{m['weighted_recall']:>10.4f} {m['weighted_f1']:>10.4f}")
    print(f"\n  Overall Accuracy : {m['accuracy']:.4f}  "
          f"({m['accuracy']*100:.2f}%)")


#  Save

def save_results(results: dict, ts: str):
    os.makedirs(RESULTS_DIR, exist_ok=True)
    base  = f"classifier_efficacy_{ts}"
    jpath = os.path.join(RESULTS_DIR, base + ".json")
    cpath = os.path.join(RESULTS_DIR, base + ".csv")

    with open(jpath, "w") as f:
        json.dump(results, f, indent=2)

    # Per-sample CSV
    rows = results.get("per_sample", [])
    if rows:
        with open(cpath, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()),
                               extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)

    print(f"\n  JSON → {jpath}")
    print(f"  CSV  → {cpath}")


#  Main

def run_pipeline(mode, dataset, port, baud, ack_timeout):
    samples   = dataset["samples"]
    per_sample = []

    sw_true, sw_pred = [], []
    fp_true, fp_pred = [], []

    ser = None
    use_replica = True

    if mode in ("hardware", "both") and port:
        import serial
        print(f"[efficacy] Opening {port} @ {baud} baud …")
        ser = serial.Serial(port, baud, timeout=ack_timeout)
        try:
            ser.set_low_latency_mode(True)
        except Exception:
            pass
        import time as _t; _t.sleep(2)
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        use_replica = False
    elif mode in ("hardware", "both") and not port:
        print("[efficacy] No --port supplied → using software FPGA replica.")

    print(f"[efficacy] Classifying {len(samples)} samples …")

    for s in samples:
        row = {
            "sample_id":  s["sample_id"],
            "true_label": s["true_label"],
        }

        if mode in ("software", "both"):
            pred_sw, lat_sw = software_classify(s)
            sw_true.append(s["true_label"])
            sw_pred.append(pred_sw)
            row["sw_prediction"] = pred_sw
            row["sw_latency_ms"] = round(lat_sw, 4)
            row["sw_correct"]    = int(pred_sw == s["true_label"])

        if mode in ("hardware", "both"):
            if use_replica:
                pred_fp, lat_fp = fpga_classify_replica(s)
            else:
                pred_fp, lat_fp = fpga_classify_serial(s, ser)
            fp_true.append(s["true_label"])
            fp_pred.append(pred_fp)
            row["fpga_prediction"] = pred_fp
            row["fpga_latency_ms"] = round(lat_fp, 4)
            row["fpga_correct"]    = int(pred_fp == s["true_label"])

        per_sample.append(row)

    if ser:
        ser.close()

    results = {
        "metadata": {
            "dataset":      DATASET_PATH,
            "total_samples": len(samples),
            "mode":         mode,
            "fpga_backend": "serial" if (not use_replica and mode != "software")
                            else "software_replica",
            "classes":      CLASSES,
        },
        "per_sample": per_sample,
    }

    if sw_true:
        cm_sw  = confusion_matrix(sw_true, sw_pred, CLASSES)
        m_sw   = class_metrics(cm_sw, CLASSES)
        sep    = "=" * 62
        print(f"\n{sep}")
        print("  SOFTWARE CLASSIFIER (GestureRecogniser) - Efficacy")
        print(sep)
        print_confusion_matrix(cm_sw, CLASSES, "Confusion Matrix")
        print_metrics(m_sw, "Classification Report")
        results["software_classifier"] = {
            "confusion_matrix": cm_sw.tolist(),
            "metrics":          m_sw,
            "mean_latency_ms":  round(
                sum(r["sw_latency_ms"] for r in per_sample
                    if "sw_latency_ms" in r) / len(sw_true), 4),
        }

    if fp_true:
        cm_fp = confusion_matrix(fp_true, fp_pred, CLASSES)
        m_fp  = class_metrics(cm_fp, CLASSES)
        label = ("FPGA Classifier (Hardware UART)"
                 if not use_replica else "FPGA Replica (Software)")
        sep   = "=" * 62
        print(f"\n{sep}")
        print(f"  {label} - Efficacy")
        print(sep)
        print_confusion_matrix(cm_fp, CLASSES, "Confusion Matrix")
        print_metrics(m_fp, "Classification Report")
        results["fpga_classifier"] = {
            "backend":        "serial" if not use_replica else "software_replica",
            "confusion_matrix": cm_fp.tolist(),
            "metrics":          m_fp,
            "mean_latency_ms":  round(
                sum(r["fpga_latency_ms"] for r in per_sample
                    if "fpga_latency_ms" in r) / len(fp_true), 4),
        }

    return results


def main():
    ap = argparse.ArgumentParser(
        description="Classifier efficacy benchmark (confusion matrix, P/R/F1).")
    ap.add_argument("--mode",        choices=["software","hardware","both"],
                    default="both")
    ap.add_argument("--dataset",     default=DATASET_PATH,
                    help="Path to static_gesture_dataset.json")
    ap.add_argument("--port",        default=None,
                    help="Serial port for FPGA (e.g. /dev/ttyUSB1). "
                         "Omit to use software FPGA replica.")
    ap.add_argument("--baud",        type=int, default=115200)
    ap.add_argument("--ack-timeout", type=float, default=0.5)
    args = ap.parse_args()

    if not os.path.exists(args.dataset):
        sys.exit(f"[ERROR] Dataset not found: {args.dataset}\n"
                 f"  Run: python generate_static_dataset.py")

    with open(args.dataset) as f:
        dataset = json.load(f)

    ts      = datetime.now().strftime("%Y%m%d_%H%M%S")
    results = run_pipeline(args.mode, dataset, args.port, args.baud, args.ack_timeout)
    save_results(results, ts)


if __name__ == "__main__":
    main()
