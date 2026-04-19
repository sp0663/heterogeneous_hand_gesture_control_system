import cv2
import serial
import time
from hand_tracker import HandTracker

SERIAL_PORT = "COM8"
BAUD_RATE   = 115200

tracker = HandTracker()
cap     = cv2.VideoCapture(0)
ser     = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2.0)
time.sleep(2)

def build_frame_bytes(landmarks):
    landmarks_sorted = sorted(landmarks[:21], key=lambda lm: lm[0])
    wrist_x, wrist_y = landmarks_sorted[0][1], landmarks_sorted[0][2]
    max_dist = max(
        (max(abs(lm[1]-wrist_x), abs(lm[2]-wrist_y)) for lm in landmarks_sorted),
        default=1
    ) or 1

    frame = bytearray()
    sent = []
    for lm in landmarks_sorted:
        lm_id = lm[0]
        nx = max(0, min(65535, int(((lm[1]-wrist_x)/max_dist + 1)*32767)))
        ny = max(0, min(65535, int(((lm[2]-wrist_y)/max_dist + 1)*32767)))
        frame.append(lm_id & 0x1F)
        frame.append((nx >> 8) & 0xFF)
        frame.append(nx & 0xFF)
        frame.append((ny >> 8) & 0xFF)
        frame.append(ny & 0xFF)
        sent.append((lm_id, nx, ny))
    return frame, sent

def parse_echo(data):
    """Parse 105 bytes back into list of (id, x, y)"""
    result = []
    for i in range(21):
        base = i * 5
        if base + 4 >= len(data):
            break
        lm_id = data[base] & 0x1F
        x = (data[base+1] << 8) | data[base+2]
        y = (data[base+3] << 8) | data[base+4]
        result.append((lm_id, x, y))
    return result

ser.reset_input_buffer()
ser.reset_output_buffer()

frame_count = 0

while True:
    success, img = cap.read()
    if not success:
        break

    img = tracker.find_hands(img, draw=True)
    landmarks, hand_label = tracker.get_landmarks(img)

    if len(landmarks) >= 21:
        payload, sent = build_frame_bytes(landmarks)

        ser.reset_input_buffer()
        ser.write(payload)
        ser.flush()
        frame_count += 1

        # Read back 105 bytes
        echo = ser.read(105)
        if len(echo) != 105:
            print(f"[Frame {frame_count}] ERROR: got {len(echo)}/105 bytes back")
            ser.reset_input_buffer()
            continue

        received = parse_echo(echo)

        # Compare sent vs received
        mismatch = False
        for s, r in zip(sent, received):
            if s != r:
                print(f"  MISMATCH LM{s[0]}: sent=({s[1]},{s[2]}) got=({r[1]},{r[2]})")
                mismatch = True

        if not mismatch:
            print(f"[Frame {frame_count}] OK — all 21 landmarks match")
        else:
            print(f"[Frame {frame_count}] MISMATCH detected — see above")

    cv2.imshow("Hand Tracker", img)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
ser.close()
cv2.destroyAllWindows()
