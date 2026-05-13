# ~/project/files/app/main.py

from fastapi import FastAPI
from sqlalchemy import create_engine, text
from prometheus_fastapi_instrumentator import Instrumentator
import socket

app = FastAPI(title="Project API")
Instrumentator().instrument(app).expose(app)

DB_URL = "postgresql://appuser:apppass123@192.168.61.136:5432/appdb"
engine = create_engine(DB_URL, pool_pre_ping=True)

@app.get("/health")
def health():
    return {"status": "ok", "server": socket.gethostname()}

@app.get("/items")
def get_items():
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT * FROM items")).fetchall()
        return {"items": [dict(r._mapping) for r in rows]}

@app.post("/items")
def create_item(name: str):
    with engine.connect() as conn:
        conn.execute(
            text("INSERT INTO items (name, server) VALUES (:n, :s)"),
            {"n": name, "s": socket.gethostname()}
        )
        conn.commit()
    return {"created": name, "by": socket.gethostname()}
