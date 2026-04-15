import cv2
import base64
from ultralytics import solutions, YOLO
from backend.app.state import latest_data 
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
model_path = str(BASE_DIR / "camera_model.pt")

print(f"Loading model from: {model_path}")


region_points = {
    "region-01": [(0, 20), (300, 20), (300, 250), (250, 400), (0, 400)],
    "region-02": [(340, 250), (340, 20), (640, 20), (640, 400), (400, 400)],
}


def _normalize_label(label):
    return str(label).strip().lower().replace("_", " ").replace("-", " ")


def _build_breakdown(class_counts):
    breakdown = {
        "childMale": 0,
        "adultMale": 0,
        "seniorMale": 0,
        "childFemale": 0,
        "adultFemale": 0,
        "seniorFemale": 0,
    }

    for raw_name, count in class_counts.items():
        normalized = _normalize_label(raw_name)
        n = int(count) if isinstance(count, (int, float)) else 0

        if "male" in normalized and "female" not in normalized:
            if "child" in normalized:
                breakdown["childMale"] += n
            elif "senior" in normalized:
                breakdown["seniorMale"] += n
            elif "adult" in normalized:
                breakdown["adultMale"] += n
        elif "female" in normalized:
            if "child" in normalized:
                breakdown["childFemale"] += n
            elif "senior" in normalized:
                breakdown["seniorFemale"] += n
            elif "adult" in normalized:
                breakdown["adultFemale"] += n

    return breakdown

def _open_camera():
    """Try multiple backends to open the camera."""
    backends = [
        ("DirectShow", cv2.CAP_DSHOW),
        ("MSMF", cv2.CAP_MSMF),
        ("Default", cv2.CAP_ANY),
    ]
    for name, api in backends:
        cap = cv2.VideoCapture(0, api)
        if cap.isOpened():
            print(f"[capture] Camera opened with {name} backend")
            return cap
        cap.release()
        print(f"[capture] {name} backend failed")
    return None


def passenger_count_capture():
    import time

    max_retries = 10
    cap = None
    for attempt in range(max_retries):
        cap = _open_camera()
        if cap is not None:
            print(f"[capture] Camera ready on attempt {attempt + 1}")
            break
        print(f"[capture] No backend could open camera, retrying ({attempt + 1}/{max_retries})…")
        time.sleep(2)
    else:
        print("[capture] ERROR: Could not open camera after retries. Capture thread exiting.")
        return

    regionCounter = solutions.RegionCounter(
        show=False,
        region=region_points,
        model=model_path,
    )
    yolo = regionCounter.model

    consecutive_failures = 0
    while True:
        try:
            if not cap.isOpened():
                print("[capture] Camera closed unexpectedly, reopening…")
                time.sleep(2)
                cap = _open_camera()
                if cap is None:
                    print("[capture] Could not reopen camera, waiting…")
                    time.sleep(5)
                    continue

            success, im0 = cap.read()
            if not success:
                consecutive_failures += 1
                time.sleep(0.1)  # prevent CPU spin on repeated failures
                if consecutive_failures > 30:
                    print("[capture] Too many consecutive frame failures, reopening camera…")
                    cap.release()
                    time.sleep(2)
                    cap = _open_camera()
                    if cap is None:
                        cap = cv2.VideoCapture(0)  # last resort
                    consecutive_failures = 0
                continue
            consecutive_failures = 0

            frame = im0.copy()

            results = regionCounter(im0)
            yolo_results = yolo(frame, verbose=False)

            class_counts = {}
            for box in yolo_results[0].boxes:
                cls_name = yolo_results[0].names[int(box.cls)]
                class_counts[cls_name] = class_counts.get(cls_name, 0) + 1

            # Get annotated frame with regions drawn
            annotated_frame = results.plot() if hasattr(results, 'plot') else im0

            # Encode frame to base64
            _, buffer = cv2.imencode('.jpg', annotated_frame,
                                     [cv2.IMWRITE_JPEG_QUALITY, 70])
            frame_b64 = base64.b64encode(buffer).decode('utf-8')

            # Update state
            breakdown = _build_breakdown(class_counts)
            latest_data["region_counts"] = results.region_counts
            latest_data["class_counts"] = class_counts
            latest_data["breakdown"] = breakdown
            latest_data["total_passenger_counts"] = sum(class_counts.values())
            latest_data["frame"] = frame_b64

        except Exception as e:
            print(f"[capture] Unexpected error: {e}")
            time.sleep(1)  # prevent tight spin on repeated exceptions