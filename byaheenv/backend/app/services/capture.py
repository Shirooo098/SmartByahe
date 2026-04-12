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

def passenger_count_capture():
    cap = cv2.VideoCapture(0)
    regionCounter = solutions.RegionCounter(
        show=False,
        region=region_points,
        model=model_path,
    )
    yolo = regionCounter.model

    while cap.isOpened():
        success, im0 = cap.read()
        if not success:
            break

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
        latest_data["region_counts"] = results.region_counts
        latest_data["class_counts"] = class_counts
        latest_data["total_passenger_counts"] = sum(class_counts.values())
        latest_data["frame"] = frame_b64  # ← add frame to state