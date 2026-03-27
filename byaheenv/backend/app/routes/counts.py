from fastapi import APIRouter
from backend.app.state import latest_data

router = APIRouter()

@router.get("/counts")
async def get_counts():
    return latest_data