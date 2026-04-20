"""
Latency Benchmarking Script for Gesture Recognition System
Jetson Orin Nano + Nexys 4 DDR FPGA pipeline
Measures per-stage latency breakdown end-to-end
"""

import cv2
import time
import serial
import numpy as np
from collections import defaultdict
import json
from hand_tracker import HandTracker
from media_controller import MediaController
from config import GESTURE_HOLD_TIME, DEBUG

SERIAL_PORT = "/dev/ttyUSB0"
BAUD_RATE   = 115200

GESTURE_NAMES = {
    0: "pinch",
    1: "fist",
    2: "open_palm",
    3: "index_finger",
    4: "unknown",
    5: "pinch_clockwise",
    6: "pinch_anticlockwise"
}

class LatencyBenchmark:
    def __init__(self, num_samples=1000):
        self.num_samples  = num_samples
        self.results      = defaultdict(list)
        self.tracker      = HandTracker()
        self.controller   = MediaController()

        # Open serial port
        self.ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.5)
        try:
            # Reduce FTDI latency timer on Linux for consistent timing
            self.ser.set_low_latency_mode(True)
        except Exception:
            pass
        time.sleep(2)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def build_frame_bytes(self, landmarks):
        landmarks_sorted = sorted(landmarks[:21], key=lambda lm: lm[0])
        wrist_x, wrist_y = landmarks_sorted[0][1], landmarks_sorted[0][2]
        max_dist = max(
            (max(abs(lm[1]-wrist_x), abs(lm[2]-wrist_y))
             for lm in landmarks_sorted),
            default=1
        ) or 1
        frame = bytearray()
        for lm in landmarks_sorted:
            lm_id = lm[0]
            nx = max(0, min(65535, int(((lm[1]-wrist_x)/max_dist + 1)*32767)))
            ny = max(0, min(65535, int(((lm[2]-wrist_y)/max_dist + 1)*32767)))
            frame.append(lm_id & 0x1F)
            frame.append((nx >> 8) & 0xFF)
            frame.append(nx & 0xFF)
            frame.append((ny >> 8) & 0xFF)
            frame.append(ny & 0xFF)
        return frame

    def measure_pipeline(self):
        cap = cv2.VideoCapture(0)
        print(f"Starting benchmark ({self.num_samples} samples)...")
        print("Show different gestures during measurement\n")

        sample_count = 0

        while sample_count < self.num_samples:

            # ── STAGE 1: Camera Capture ──────────────────────────
            t0 = time.perf_counter()
            success, frame = cap.read()
            frame = cv2.flip(frame, 1)
            t1 = time.perf_counter()
            if not success:
                continue
            capture_ms = (t1 - t0) * 1000

            # ── STAGE 2: MediaPipe Hand Detection ────────────────
            t2 = time.perf_counter()
            frame = self.tracker.find_hands(frame, draw=False)
            landmarks, hand_label = self.tracker.get_landmarks(frame)
            t3 = time.perf_counter()
            mediapipe_ms = (t3 - t2) * 1000

            if len(landmarks) < 21:
                cv2.imshow("Benchmark", frame)
                if cv2.waitKey(1) & 0xFF == ord('q'):
                    break
                continue

            # ── STAGE 3: Landmark Normalisation & Serialisation ──
            t4 = time.perf_counter()
            payload = self.build_frame_bytes(landmarks)
            t5 = time.perf_counter()
            serialise_ms = (t5 - t4) * 1000

            # ── STAGE 4: UART TX to FPGA ─────────────────────────
            self.ser.reset_input_buffer()
            t6 = time.perf_counter()
            self.ser.write(payload)
            self.ser.flush()
            t7 = time.perf_counter()
            uart_tx_ms = (t7 - t6) * 1000

            # ── STAGE 5: FPGA Pipeline + UART RX ─────────────────
            t8 = time.perf_counter()
            ack = self.ser.read(1)
            t9 = time.perf_counter()
            fpga_rx_ms = (t9 - t8) * 1000

            if len(ack) != 1:
                # Timeout — skip this sample
                self.ser.reset_input_buffer()
                self.ser.reset_output_buffer()
                continue

            gesture_id   = ack[0] & 0x07
            gesture_name = GESTURE_NAMES.get(gesture_id, f"ID={gesture_id}")

            # ── STAGE 6: Command Mapping Lookup ──────────────────
            t10 = time.perf_counter()
            from config import GESTURE_COMMANDS, VLC_KEYS
            if gesture_name in GESTURE_COMMANDS:
                command = GESTURE_COMMANDS[gesture_name]
                if command in VLC_KEYS:
                    _ = VLC_KEYS[command]
            t11 = time.perf_counter()
            command_ms = (t11 - t10) * 1000

            # ── Totals ────────────────────────────────────────────
            # UART floor: 105 bytes TX + 1 byte RX at 115200 baud
            uart_floor_ms = (105 + 1) * 10 / 115200 * 1000
            fpga_pipeline_ms = max(0, fpga_rx_ms - uart_floor_ms)
            total_ms = capture_ms + mediapipe_ms + serialise_ms + uart_tx_ms + fpga_rx_ms + command_ms

            # Store
            self.results['capture'].append(capture_ms)
            self.results['mediapipe'].append(mediapipe_ms)
            self.results['serialise'].append(serialise_ms)
            self.results['uart_tx'].append(uart_tx_ms)
            self.results['fpga_and_uart_rx'].append(fpga_rx_ms)
            self.results['fpga_pipeline'].append(fpga_pipeline_ms)
            self.results['command_mapping'].append(command_ms)
            self.results['total'].append(total_ms)
            self.results['gesture_type'].append(gesture_name)

            sample_count += 1

            if sample_count % 10 == 0:
                print(f"  [{sample_count:4d}/{self.num_samples}] "
                      f"total={total_ms:6.2f}ms  "
                      f"fpga={fpga_rx_ms:6.2f}ms  "
                      f"mediapipe={mediapipe_ms:6.2f}ms  "
                      f"gesture={gesture_name}")

            cv2.imshow("Benchmark (Q to stop)", frame)
            if cv2.waitKey(1) & 0xFF == ord('q'):
                break

        cap.release()
        cv2.destroyAllWindows()
        self.ser.close()
        print(f"\nCollected {sample_count} samples")
        return sample_count

    def calculate_statistics(self):
        stats = {}
        stages = [
            'capture', 'mediapipe', 'serialise',
            'uart_tx', 'fpga_and_uart_rx', 'fpga_pipeline',
            'command_mapping', 'total'
        ]
        for stage in stages:
            data = np.array(self.results[stage])
            stats[stage] = {
                'mean':   float(np.mean(data)),
                'std':    float(np.std(data)),
                'min':    float(np.min(data)),
                'max':    float(np.max(data)),
                'median': float(np.median(data)),
                'p95':    float(np.percentile(data, 95)),
                'p99':    float(np.percentile(data, 99))
            }
        return stats

    def calculate_jitter(self):
        total = np.array(self.results['total'])
        diffs = np.diff(total)
        return {
            'mean': float(np.mean(np.abs(diffs))),
            'std':  float(np.std(diffs)),
            'max':  float(np.max(np.abs(diffs)))
        }

    def calculate_fps(self):
        avg = np.mean(self.results['total']) / 1000
        return 1.0 / avg if avg > 0 else 0

    def print_results(self, stats, jitter, fps):
        uart_floor = (105 + 1) * 10 / 115200 * 1000

        print("\n" + "="*75)
        print("  GESTURE RECOGNITION LATENCY BENCHMARK")
        print("  Jetson Orin Nano + Nexys 4 DDR FPGA")
        print("="*75)

        stage_names = {
            'capture':           'Camera Capture',
            'mediapipe':         'MediaPipe Detection',
            'serialise':         'Landmark Normalisation',
            'uart_tx':           'UART TX (105 bytes)',
            'fpga_and_uart_rx':  'FPGA Pipeline + UART RX',
            'fpga_pipeline':     '  └─ FPGA only (est.)',
            'command_mapping':   'Command Mapping',
            'total':             'TOTAL END-TO-END'
        }

        print(f"\n{'Stage':<28} {'Mean':>8} {'Std':>8} {'Min':>8} {'Max':>8} {'P95':>8}")
        print("-"*75)

        for stage in ['capture', 'mediapipe', 'serialise',
                      'uart_tx', 'fpga_and_uart_rx', 'fpga_pipeline',
                      'command_mapping']:
            s = stats[stage]
            print(f"{stage_names[stage]:<28} "
                  f"{s['mean']:>7.2f}ms {s['std']:>7.2f}ms "
                  f"{s['min']:>7.2f}ms {s['max']:>7.2f}ms "
                  f"{s['p95']:>7.2f}ms")

        print("-"*75)
        s = stats['total']
        print(f"{'TOTAL END-TO-END':<28} "
              f"{s['mean']:>7.2f}ms {s['std']:>7.2f}ms "
              f"{s['min']:>7.2f}ms {s['max']:>7.2f}ms "
              f"{s['p95']:>7.2f}ms")

        print(f"\n  UART theoretical floor : {uart_floor:.2f} ms")

        print(f"\n{'PERCENTAGE BREAKDOWN':}")
        print("-"*75)
        total_mean = stats['total']['mean']
        for stage in ['capture', 'mediapipe', 'serialise',
                      'uart_tx', 'fpga_and_uart_rx', 'command_mapping']:
            pct = (stats[stage]['mean'] / total_mean) * 100
            bar = '█' * int(pct / 2)
            print(f"  {stage_names[stage]:<26} {pct:>5.1f}%  {bar}")

        print(f"\n{'JITTER ANALYSIS':}")
        print("-"*75)
        print(f"  Mean jitter    : {jitter['mean']:.2f} ms")
        print(f"  Jitter std dev : {jitter['std']:.2f} ms")
        print(f"  Max jitter     : {jitter['max']:.2f} ms")
        verdict = ("CONSISTENT ✓" if jitter['mean'] < 1.0
                   else "MOSTLY CONSISTENT" if jitter['mean'] < 3.0
                   else "HIGH JITTER — check USB latency timer")
        print(f"  Verdict        : {verdict}")

        print(f"\n{'FRAME RATE & TARGETS':}")
        print("-"*75)
        print(f"  Effective FPS  : {fps:.1f} fps")
        print(f"  Target ≥15 FPS : {'PASS ✓' if fps >= 15 else 'FAIL ✗'}")
        print(f"  Mean latency   : {stats['total']['mean']:.2f} ms")
        print(f"  Target <200ms  : {'PASS ✓' if stats['total']['mean'] < 200 else 'FAIL ✗'}")

        print(f"\n{'GESTURE DISTRIBUTION':}")
        print("-"*75)
        gestures = self.results['gesture_type']
        unique, counts = np.unique(gestures, return_counts=True)
        for g, c in zip(unique, counts):
            print(f"  {g:<20} {c:>5} samples  ({c/len(gestures)*100:>5.1f}%)")

        print("\n" + "="*75)

    def save_results(self, filename='benchmark_results.json'):
        stats  = self.calculate_statistics()
        jitter = self.calculate_jitter()
        fps    = self.calculate_fps()

        output = {
            'system': {
                'platform':    'Jetson Orin Nano',
                'fpga':        'Nexys 4 DDR (Artix-7)',
                'baud_rate':   BAUD_RATE,
                'uart_floor_ms': (105+1)*10/115200*1000
            },
            'summary': {
                'total_samples':   len(self.results['total']),
                'mean_latency_ms': stats['total']['mean'],
                'fps':             fps,
                'jitter':          jitter
            },
            'per_stage_stats': stats,
            'raw_data': {
                k: [float(v) for v in vals]
                for k, vals in self.results.items()
                if k != 'gesture_type'
            },
            'gesture_types': self.results['gesture_type']
        }

        with open(filename, 'w') as f:
            json.dump(output, f, indent=2)
        print(f"\nResults saved to: {filename}")

    def run(self, save_json=True):
        print("Gesture Recognition Latency Benchmark")
        print("Jetson Orin Nano + Nexys 4 DDR FPGA")
        print("="*75)
        input("Press ENTER to start, then show different gestures...\n")

        samples = self.measure_pipeline()
        if samples == 0:
            print("No samples collected. Retry with hand visible.")
            return

        stats  = self.calculate_statistics()
        jitter = self.calculate_jitter()
        fps    = self.calculate_fps()

        self.print_results(stats, jitter, fps)
        if save_json:
            self.save_results()


if __name__ == "__main__":
    benchmark = LatencyBenchmark(num_samples=1000)
    benchmark.run(save_json=True)
