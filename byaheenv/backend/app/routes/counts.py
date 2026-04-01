from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from backend.app.state import latest_data
import asyncio
import json

router = APIRouter()

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