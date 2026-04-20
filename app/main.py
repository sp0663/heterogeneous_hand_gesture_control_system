import cv2
import serial
import time
from hand_tracker import HandTracker
from media_controller import MediaController
from config import GESTURE_HOLD_TIME, DEBUG

SERIAL_PORT  = "COM8"
BAUD_RATE    = 115200
ACK_TIMEOUT  = 0.5       # 500ms — enough for 105 bytes + pipeline latency

GESTURE_NAMES = {
    0: "pinch",
    1: "fist",
    2: "open_palm",
    3: "index_finger",
    4: "unknown",
    5: "pinch_clockwise",
    6: "pinch_anticlockwise"
}

# Debouncing variables
gesture_start_time = None
last_gesture = None
triggered = False

# Enable/Disable system variable
gestures_enabled = True 

tracker = HandTracker()
controller = MediaController()
cap     = cv2.VideoCapture(0)
ser     = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=ACK_TIMEOUT)
time.sleep(2)


def build_frame_bytes(landmarks):
    """
    Sort landmarks by ID first to guarantee correct order.
    For each of 21 landmarks: [id, x_high, x_low, y_high, y_low]
    Total: 105 bytes per frame.
    Coordinates normalised relative to wrist, scaled to [0, 65535].
    """
    # Sort by landmark ID to guarantee order 0-20
    landmarks_sorted = sorted(landmarks[:21], key=lambda lm: lm[0])

    wrist_x, wrist_y = landmarks_sorted[0][1], landmarks_sorted[0][2]
    max_dist = max(
        (max(abs(lm[1] - wrist_x), abs(lm[2] - wrist_y))
         for lm in landmarks_sorted),
        default=1
    ) or 1

    frame = bytearray()
    for lm in landmarks_sorted:
        lm_id = lm[0]
        nx = max(0, min(65535, int(((lm[1] - wrist_x) / max_dist + 1) * 32767)))
        ny = max(0, min(65535, int(((lm[2] - wrist_y) / max_dist + 1) * 32767)))

        frame.append(lm_id & 0x1F)        # ID  (5-bit safe)
        frame.append((nx >> 8) & 0xFF)    # X high
        frame.append(nx & 0xFF)           # X low
        frame.append((ny >> 8) & 0xFF)    # Y high
        frame.append(ny & 0xFF)           # Y low

    return frame  # 105 bytes

ser.reset_input_buffer()
ser.reset_output_buffer()

frame_count  = 0
no_ack_count = 0

while True:
    success, img = cap.read()
    img = cv2.flip(img, 1)
    if not success:
        break

    img = tracker.find_hands(img, draw=True)
    landmarks, hand_label = tracker.get_landmarks(img)

    if len(landmarks) >= 21:
        payload = build_frame_bytes(landmarks)

        # Flush stale ACK bytes before sending new frame
        ser.reset_input_buffer()

        ser.write(payload)
        ser.flush()
        frame_count += 1

        # Read gesture ID back
        ack = ser.read(1)
        if len(ack) == 1:
            gesture_id   = ack[0] & 0x07
            current_gesture = GESTURE_NAMES.get(gesture_id, f"ID={gesture_id}")
            # 1. TOGGLE LOGIC (Always Active)
            if current_gesture == 'index_pointing':
                if current_gesture != last_gesture:
                    gesture_start_time = time.time()
                    triggered = False
                    last_gesture = current_gesture 
                
                hold_duration = time.time() - gesture_start_time
                
                # DELIBERATE TOGGLE: 
                if hold_duration > GESTURE_HOLD_TIME and not triggered:
                    gestures_enabled = not gestures_enabled
                    triggered = True
                    if DEBUG: print(f"System Enabled: {gestures_enabled}")
                    
            # 2. NORMAL GESTURES (Only if Enabled)
            elif gestures_enabled:

                if 'pinch_' in current_gesture:
                    controller.execute_command(current_gesture)
                    triggered = True
                    last_gesture = current_gesture
                    if DEBUG: print(f"Pinch movement Detected: {current_gesture}")

                # Static gestures have to wait for hold time to prevent repeated executions
                elif current_gesture == last_gesture and current_gesture != 'unknown':
                    hold_duration = time.time() - gesture_start_time
                    if hold_duration > GESTURE_HOLD_TIME and not triggered:
                        controller.execute_command(current_gesture)
                        triggered = True
                        if DEBUG: print(f"Held Gesture Executed: {current_gesture}")
                
                elif current_gesture != last_gesture:
                    last_gesture = current_gesture
                    gesture_start_time = time.time()
                    triggered = False
            
            else:
                last_gesture = None
                triggered = False
            
            # 3. UI OVERLAY LOGIC
            if not gestures_enabled:
                cv2.putText(img, "SYSTEM DISABLED", (10, 50), 
                            cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
                progress_label = "Hold Index to Enable"
            else:
                color = (0, 255, 0) if current_gesture != 'unknown' else (0, 165, 255)
                cv2.putText(img, f"Gesture: {current_gesture}", 
                            (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)
                progress_label = "Hold..."
                
            # Draw Progress Bar
            if gesture_start_time and current_gesture != 'unknown':
                hold_time = time.time() - gesture_start_time
                
                target_time = 2.0 if current_gesture == 'index_pointing' else GESTURE_HOLD_TIME
                progress = min(hold_time / target_time, 1.0)
                
                bar_width = 200
                bar_height = 20
                filled = int(bar_width * progress)
                
                cv2.rectangle(img, (10, 90), (10 + bar_width, 90 + bar_height), (50, 50, 50), -1)
                cv2.rectangle(img, (10, 90), (10 + filled, 90 + bar_height), (0, 255, 0), -1)
                cv2.putText(img, progress_label, (10, 85), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
                
            no_ack_count = 0
            
        else:
            no_ack_count += 1
            print(f"[Frame {frame_count}] WARNING: No ACK (timeout #{no_ack_count})")

            # After 3 misses flush everything and re-sync
            if no_ack_count >= 3:
                print("[RESYNC] Flushing and re-syncing...")
                ser.reset_input_buffer()
                ser.reset_output_buffer()
                no_ack_count = 0
                time.sleep(0.1)

    cv2.imshow("Hand Tracker", img)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
ser.close()
cv2.destroyAllWindows()