from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException
from backend.app.state import latest_data
import asyncio
import json
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

class GPSData(BaseModel):
    latitude: float
    longitude: float
    gps_valid: bool
    satellites: int
    trip_phase: Optional[str] = None
    dist_to_start_m: Optional[float] = None
    dist_to_finish_m: Optional[float] = None
    weight_g: float
    status: str

@router.post("/gps")
async def receive_gps(data: GPSData):
    latest_data.update({
        "latitude": data.latitude,
        "longitude": data.longitude,
        "gps_valid": data.gps_valid,
        "satellites": data.satellites,
        "trip_phase": data.trip_phase,
        "dist_to_start_m": data.dist_to_start_m,
        "dist_to_finish_m": data.dist_to_finish_m,
        "weight_g": data.weight_g,
        "status": data.status
    })
    return {"status": "received"}

@router.get("/gps")
async def get_gps():
    return {
        "latitude": latest_data.get("latitude", 0.0),
        "longitude": latest_data.get("longitude", 0.0),
        "gps_valid": latest_data.get("gps_valid", False),
        "satellites": latest_data.get("satellites", 0),
        "trip_phase": latest_data.get("trip_phase", "UNKNOWN"),
        "dist_to_start_m": latest_data.get("dist_to_start_m", -1.0),
        "dist_to_finish_m": latest_data.get("dist_to_finish_m", -1.0),
        "weight_g": latest_data.get("weight_g", 0.0),
        "status": latest_data.get("status", "UNKNOWN")
    }

@router.get("/counts")
async def get_counts():
    return latest_data

@router.websocket("/websocket/counts")
async def websocket_counts(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            await websocket.send_text(json.dumps(latest_data))
            await asyncio.sleep(5)
    except WebSocketDisconnect:
        print("Client Disconnected")

@router.websocket("/websocket/stream")
async def websocket_stream(websocket: WebSocket):
    """Streams annotated frames + counts at ~30fps."""
    await websocket.accept()
    try:
        while True:

            if latest_data.get("frame"):
                payload = json.dumps({
                    "frame": latest_data["frame"],           # base64 JPEG string
                    "region_counts": latest_data.get("region_counts", {}),
                    "class_counts": latest_data.get("class_counts", {}),
                    "total": latest_data.get("total_passenger_counts", 0),
                })
                await websocket.send_text(payload)
            await asyncio.sleep(1 / 30)  # ~30fps cap
    except WebSocketDisconnect:
        print("Stream client disconnected")