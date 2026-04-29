from fastapi import FastAPI
from src.api.chat import router as chat_router

app = FastAPI(title="NJ Stream AI Service", version="0.1.0")
app.include_router(chat_router)
