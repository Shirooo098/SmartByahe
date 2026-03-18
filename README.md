# SmartByahe 🚌

A computer vision system for detecting and classifying bus passengers by demographic group using YOLOv2-6n object detection.

---

## Overview

SmartByahe uses a custom-trained YOLO model to detect and classify passengers inside a bus into six demographic categories. This can be used for passenger analytics, capacity planning, or accessibility monitoring.

---

## Model

| Property | Details |
|----------|---------|
| Architecture | YOLO26n (YOLOv2-6 Nano) |
| Parameters | 2,376,006 |
| GFLOPs | 5.2 |
| Layers | 122 (fused) |
| Input Size | 640x640 |
| Framework | Ultralytics |

---

## Dataset

Sourced from [Roboflow Universe](https://universe.roboflow.com/johns-workspace-dsz12/bus_passenger/dataset/1).

| Property | Details |
|----------|---------|
| Project | bus_passenger |
| Version | 1 |
| License | CC BY 4.0 |
| Train Images | 96 |
| Val Images | 28 |
| Classes | 6 |

### Classes

- Adult Female
- Adult Male
- Child Female
- Child Male
- Senior Female
- Senior Male

---

## Performance

Evaluated on 28 validation images (334 instances):

| Class | Images | Instances | Precision | Recall | mAP50 | mAP50-95 |
|-------|--------|-----------|-----------|--------|-------|----------|
| **All** | 28 | 334 | 0.895 | 0.874 | 0.913 | 0.849 |
| Adult Female | 28 | 66 | 0.821 | 0.764 | 0.868 | 0.806 |
| Adult Male | 25 | 52 | 0.850 | 0.923 | 0.901 | 0.870 |
| Child Female | 25 | 44 | 0.896 | 0.781 | 0.867 | 0.751 |
| Child Male | 22 | 45 | 0.904 | 0.839 | 0.907 | 0.842 |
| Senior Female | 26 | 60 | 0.929 | 0.983 | 0.942 | 0.890 |
| Senior Male | 27 | 67 | 0.972 | 0.955 | 0.993 | 0.937 |

> Training stopped early at epoch 336/500 (best checkpoint at epoch 236).

---

## Installation

```bash
pip install ultralytics
```

---

## Project Structure

```
SmartByahe/
├── dataset/
│   ├── train/
│   │   ├── images/
│   │   └── labels/
│   ├── valid/
│   │   ├── images/
│   │   └── labels/
│   └── test/
│       ├── images/
│       └── labels/
├── data.yaml
├── yolo26n.pt
└── runs/
    └── detect/
        └── train13/
            └── weights/
                ├── best.pt
                └── last.pt
```

---

## Usage

### Training

```python
from ultralytics import YOLO

model = YOLO("yolo26n.pt")
model.train(
    data="./dataset/data.yaml",
    epochs=500,
    patience=50,
    imgsz=640,
    plots=True
)
```

### Validation

```python
metrics = model.val()
print(f"mAP50:    {metrics.box.map50:.3f}")
print(f"mAP50-95: {metrics.box.map:.3f}")
```

### Inference

```python
from ultralytics import YOLO

model = YOLO("runs/detect/train13/weights/best.pt")

# Single image
results = model.predict("bus_image.jpg", conf=0.5, save=True, show=True)

# Webcam / live feed
results = model.predict(source=0, conf=0.5, show=True)

# Print detections
for r in results:
    for box in r.boxes:
        cls = model.names[int(box.cls)]
        conf = float(box.conf)
        print(f"Detected: {cls} ({conf:.2f})")
```

### Export to CSV

```python
import pandas as pd
import glob, os

image_paths = glob.glob("./dataset/test/images/*.jpg")
records = []

for img_path in image_paths:
    results = model.predict(img_path, conf=0.5, verbose=False)
    for r in results:
        counts = {name: 0 for name in model.names.values()}
        for box in r.boxes:
            counts[model.names[int(box.cls)]] += 1
        records.append({"image": os.path.basename(img_path),
                        "total": len(r.boxes), **counts})

pd.DataFrame(records).to_csv("predictions.csv", index=False)
```

### Export Model

```python
model.export(format="onnx")       # ONNX (cross-platform)
model.export(format="tflite")     # TensorFlow Lite (mobile)
model.export(format="openvino")   # Intel edge devices
```

---

## data.yaml

```yaml
train: ../train/images
val:   ../valid/images
test:  ../test/images

nc: 6
names:
  - Adult Female
  - Adult Male
  - Child Female
  - Child Male
  - Senior Female
  - Senior Male
```

---

## Hardware Used

| Component | Details |
|-----------|---------|
| GPU | NVIDIA GeForce RTX 3060 (12GB) |
| CUDA | 12.6 |
| PyTorch | 2.10.0 |
| Python | 3.12.10 |
| Training Time | ~0.25 hours |

---

## License

Dataset licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
