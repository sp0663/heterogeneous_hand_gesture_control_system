import cv2
from hand_tracker import HandTracker
from utils import count_extended_fingers

HEX_FILE = "landmarks_hex.txt"
CAPTURE_INTERVAL = 15

tracker = HandTracker()
cap = cv2.VideoCapture(0)
frame_count = 0

def pack_landmarks(scaled):
    x_bus, y_bus = 0, 0
    for i, (x, y) in enumerate(scaled):
        x_bus |= (x << (i * 16))
        y_bus |= (y << (i * 16))
    return x_bus, y_bus

with open(HEX_FILE, "w") as hf:
    while True:
        success, frame = cap.read()
        if not success:
            break

        frame = tracker.find_hands(frame, draw=True)
        landmarks, hand_label = tracker.get_landmarks(frame)

        if len(landmarks) > 0 and frame_count % CAPTURE_INTERVAL == 0:
            wrist_x, wrist_y = landmarks[0][1], landmarks[0][2]
            max_dist = max((max(abs(lm[1] - wrist_x), abs(lm[2] - wrist_y)) for lm in landmarks), default=1) or 1

            scaled = []
            for lm in landmarks[:21]:
                nx = max(0, min(65535, int(((lm[1] - wrist_x) / max_dist + 1) * 32767)))
                ny = max(0, min(65535, int(((lm[2] - wrist_y) / max_dist + 1) * 32767)))
                scaled.append((nx, ny))

            x_bus, y_bus = pack_landmarks(scaled)
            hf.write(f"send_frame(336'h{x_bus:084x}, 336'h{y_bus:084x});\n")
            hf.flush()

        frame_count += 1
        cv2.imshow("Capture", frame)
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

cap.release()
cv2.destroyAllWindows()
