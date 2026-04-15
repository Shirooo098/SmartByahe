# routes/stream.py
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from backend.app.state import latest_data
import asyncio
import json

router = APIRouter()

@router.websocket("/ws/stream")
async def websocket_stream(websocket: WebSocket):
    """Streams annotated frames + counts at ~30fps."""
    await websocket.accept()
    try:
        while True:
            # Only send if a frame exists
            if latest_data.get("frame"):
                payload = json.dumps({
                    "frame": latest_data["frame"],           
                    "region_counts": latest_data.get("region_counts", {}),
                    "class_counts": latest_data.get("class_counts", {}),
                    "breakdown": latest_data.get("breakdown", {}),
                    "total": latest_data.get("total_passenger_counts", 0),
                })
                await websocket.send_text(payload)
            await asyncio.sleep(1 / 30)  # ~30fps cap
    except WebSocketDisconnect:
        print("Stream client disconnected")