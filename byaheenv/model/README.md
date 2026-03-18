# SmartByahe 🚌

A Proof of Concept (POC) using computer vision system for detecting and classifying bus passengers by demographic group through clay models using YOLOv26 object detection.

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
To add more dataset, as current 139 images of dataset is not enough.
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
pip install -r requirements.txt
```

---

## Project Structure

```
SMARTBYAHE/
├── byaheenv/                   Virtual environment (gitignored)
│   ├── Include/
│   ├── Lib/
│   ├── Scripts/
│   └── pyvenv.cfg
│
├── model/                      ML work 
│   ├── dataset/
│   ├── runs/
│   ├── main.ipynb
│   ├── requirements.txt
│   ├── yolo26n.pt
│   └── yolov8n.pt
│
├── .env
├── .gitignore
└── README.md
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
