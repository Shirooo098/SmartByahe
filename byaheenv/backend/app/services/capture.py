import cv2
from ultralytics import solutions, YOLO
from backend.app.state import latest_data 

model_path = "../../camera_model.py"

region_points = {
    "region-01": [(0, 20), (300, 20), (300, 400), (0, 400)],
    "region-02": [(340, 20), (640, 20), (640, 400), (340, 400)],
}

def passenger_count_capture():
    cap = cv2.VideoCapture(0)
    yolo = YOLO(model_path)
    regionCounter = solutions.RegionCounter(
        show=False,
        region=region_points,
        model=model_path,
    )

    while cap.isOpened():
        success, im0 = cap.read()
        if not success:
            break

        results = regionCounter(im0)
        yolo_results = yolo(im0, verbose=False)

        class_counts = {}
        for box in yolo_results[0].boxes:
            cls_name = yolo_results[0].names[int(box.cls)]
            class_counts[cls_name] = class_counts.get(cls_name, 0) + 1

        # Update shared state
        latest_data["region_counts"] = results.region_counts
        latest_data["class_counts"] = class_counts