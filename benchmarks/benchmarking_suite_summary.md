# Comparative Benchmarking Suite — Delivery Summary

**Location:** `c:\Users\jishu\Desktop\miniproject\comparative_benchmarks\`

## Files Generated

| File | Size | Purpose |
|---|---|---|
| `generate_static_dataset.py` | 4.9 KB | Step 0 – Creates reproducible synthetic landmark dataset |
| `benchmark_homogeneous.py` | 11.3 KB | Step 1 – Pure-Jetson pipeline latency benchmark |
| `benchmark_heterogeneous.py` | 14.5 KB | Step 2 – Jetson+FPGA UART pipeline benchmark |
| `parse_tegrastats.py` | 13.0 KB | Step 3 – Power & resource logger |
| `benchmark_classifier_efficacy.py` | 17.5 KB | Step 4 – Confusion matrix / P/R/F1 |
| `README.md` | 16.9 KB | Complete execution & manual measurement protocol |

---

## Quick-Start Order (on the Jetson)

```bash
cd /path/to/miniproject/comparative_benchmarks

# Step 0 — generate static dataset (once)
python3 generate_static_dataset.py

# Step 1 — homogeneous benchmark (Terminal A)
# Terminal B simultaneously: python3 parse_tegrastats.py --tag homo_run1 --duration 90
python3 benchmark_homogeneous.py --samples 500 --no-display

# Step 2 — heterogeneous benchmark (Terminal A)
# Terminal B simultaneously: python3 parse_tegrastats.py --tag hetero_run1 --duration 90
python3 benchmark_heterogeneous.py --samples 500 --port /dev/ttyUSB1 --no-display

# Step 4 — classifier efficacy (no FPGA needed for software mode)
python3 benchmark_classifier_efficacy.py --mode software
python3 benchmark_classifier_efficacy.py --mode both --port /dev/ttyUSB1
```

All outputs land in `comparative_benchmarks/results/`.

---

## Metrics Captured Per Script

### benchmark_homogeneous.py
| Stage | Metric |
|---|---|
| Camera Capture | mean/std/p95/p99 ms |
| MediaPipe Detection | mean/std/p95/p99 ms |
| Gesture Recognition | mean/std/p95/p99 ms |
| Command Mapping | mean/std/p95/p99 ms |
| **Total End-to-End** | mean/std/p95/p99 ms |
| Throughput | Effective FPS |
| Jitter | mean-abs/std/max inter-frame delta ms |
| Gesture distribution | counts per class |

### benchmark_heterogeneous.py
All homogeneous stages plus:

| Stage | Metric |
|---|---|
| Serialisation (build_frame_bytes) | mean/std/p95 ms |
| UART TX (105 bytes) | mean/std/p95 ms |
| FPGA Pipeline + UART RX | mean/std/p95 ms |
| **FPGA-only estimate** | `stage5 − 9.197 ms floor` |
| UART overhead | total ms + % of pipeline |

### parse_tegrastats.py
| Metric | Source |
|---|---|
| CPU per-core utilisation (%) | `CPU [X%@MHz,...]` |
| GPU utilisation (%) | `GPC_FREQ X%@MHz` |
| RAM used/total (MB) | `RAM X/YMB` |
| Total board power (W) | Sum of all `VDD_*` rails |
| CPU rail power (W) | `VDD_CPU_GPU_CV` |
| SoC rail power (W) | `VDD_SOC` |
| Die temperatures (°C) | `CPU@X GPU@X tj@X` |

### benchmark_classifier_efficacy.py
| Metric | Both Pipelines |
|---|---|
| Confusion matrix (4×4) | fist / open_palm / index_finger / pinch |
| Per-class Precision | True positives / (TP+FP) |
| Per-class Recall | True positives / (TP+FN) |
| Per-class F1-Score | Harmonic mean P/R |
| Macro average P/R/F1 | Unweighted class mean |
| Weighted average P/R/F1 | Support-weighted class mean |
| Overall accuracy | Correct / total |
| Mean classification latency | ms per sample |

---

## Key Design Decisions

### Dataset (generate_static_dataset.py)
- Four gesture classes that exist in **both** classifiers' output spaces
- Wrist-anchored pixel-space coordinates satisfy all geometric rules used by `GestureRecogniser` (angle > 160° for extension, distance ratio for pinch)
- Gaussian noise (σ=4 px default) models real MediaPipe jitter
- Each sample stores three representations: pixel-space (→ software), normalised uint16 (→ FPGA replica), 105-byte UART frame (→ live FPGA)

### Pinch State Fix (efficacy benchmark)
`GestureRecogniser.recognise_gesture()` stores `prev_angle` across calls. On the **first call ever**, `prev_angle=None` → pinch always returns `'unknown'`. The script primes each fresh recognizer instance with one silent call (same landmarks), then times the second call — mirroring how the live pipeline classifies across successive camera frames.

### FPGA Software Replica
`fpga_replica_classify()` reimplements `gesture_classifier.v`:
- Pinch: `dist(lm4, lm8)² × 16 < dist(lm0, lm12)²`  (mirrors Verilog `wire is_pinch`)
- Extension: angle at PIP/IP joint > 160° (mirrors `angle_calculator.v`)
- Classification priority: Pinch → Fist → Open Palm → Index → Unknown

### Python Compatibility
All type hints use `typing.Optional/Dict/List` (not `X|Y` / `list[dict]`) for Python 3.8/3.9 compatibility with Jetpack 5.x.

---

## Manual Measurement Checklist

> Full step-by-step instructions are in `README.md §Manual Measurement Protocol`

- [ ] **Vivado Utilisation Report** — LUT / FF / DSP / BRAM counts + Util%
- [ ] **Vivado Power Report** — Dynamic / Static / Total on-chip power (W)
- [ ] **Vivado Timing Summary** — WNS, TNS, critical path
- [ ] **Multimeter probing** — Current shunt on Nexys4 DDR VU rail (JP2) across idle / loaded states
- [ ] **Thermal imaging** — FLIR capture of Jetson SoC + FPGA die, idle and loaded, ΔT = T_hotspot − T_ambient
