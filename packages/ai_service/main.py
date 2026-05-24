from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from src.api.chat import router as chat_router
from src.api.forecast import router as forecast_router

app = FastAPI(title="NJ Stream AI Service", version="0.1.0")

@app.get("/health")
def health_check():
    return {"status": "ok"}

app.include_router(chat_router)
app.include_router(forecast_router)
