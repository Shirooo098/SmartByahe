from fastapi import FastAPI
from backend.app.routes import counts, stream
from backend.app.services.capture import passenger_count_capture
import threading
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    thread = threading.Thread(target=passenger_count_capture, daemon=True)
    thread.start()
    
    yield
    
    print("Shutting down...")

app = FastAPI(lifespan=lifespan)
app.include_router(counts.router)
app.include_router(stream.router)