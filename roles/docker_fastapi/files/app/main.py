import os
import socket
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from prometheus_fastapi_instrumentator import Instrumentator
import psycopg2
from psycopg2.extras import RealDictCursor

app = FastAPI()

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://appuser:apppass123@192.168.61.136:5432/appdb"
)


def get_db():
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    return conn


@app.on_event("startup")
def startup():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"Warning: DB not available on startup: {e}")
        print("App will start anyway and retry on each request")


@app.get("/", response_class=HTMLResponse)
def root():
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Cloud Infrastructure Project</title>
    <style>
        body { font-family: Arial, sans-serif; background: #0f172a; color: #e2e8f0;
               display: flex; justify-content: center; padding: 40px; }
        .card { background: #1e293b; border-radius: 12px; padding: 40px;
                max-width: 600px; width: 100%; }
        h1 { color: #38bdf8; }
        .badge { background: #22c55e; color: white; padding: 4px 12px;
                 border-radius: 20px; font-size: 13px; }
        .endpoint { display: flex; justify-content: space-between;
                    background: #0f172a; padding: 10px 16px; border-radius: 8px;
                    margin-bottom: 8px; text-decoration: none; color: #e2e8f0; }
        .endpoint:hover { background: #1e3a5f; }
        .method { font-size: 11px; font-weight: bold; padding: 2px 8px;
                  border-radius: 4px; }
        .get { background: #1d4ed8; }
        .post { background: #15803d; }
        .delete { background: #991b1b; }
        .stack span { background: #334155; padding: 4px 10px; border-radius: 6px;
                      font-size: 13px; margin-right: 8px; }
        .section { margin-top: 28px; }
        .section h3 { color: #94a3b8; font-size: 13px; text-transform: uppercase;
                      letter-spacing: 1px; margin-bottom: 12px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🚀 Cloud Infrastructure Project</h1>
        <p>Status: <span class="badge">● Live</span></p>
        <div class="section">
            <h3>API Endpoints</h3>
            <a class="endpoint" href="/docs">
                <span>📖 Interactive API Docs</span>
                <span class="method get">GET</span>
            </a>
            <a class="endpoint" href="/health">
                <span>❤️ Health Check</span>
                <span class="method get">GET</span>
            </a>
            <a class="endpoint" href="/items">
                <span>📦 List Items</span>
                <span class="method get">GET</span>
            </a>
            <a class="endpoint" href="/metrics">
                <span>📊 Prometheus Metrics</span>
                <span class="method get">GET</span>
            </a>
        </div>
        <div class="section stack">
            <h3>Tech Stack</h3>
            <span>🐳 Docker</span>
            <span>⚡ FastAPI</span>
            <span>🐘 PostgreSQL</span>
            <span>📡 Nginx</span>
            <span>☁️ Cloudflare</span>
        </div>
    </div>
</body>
</html>
"""


@app.get("/health")
def health():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return {
            "status": "ok",
            "database": "connected",
            "server": socket.gethostname()
        }
    except Exception as e:
        return {
            "status": "ok",
            "database": "disconnected",
            "server": socket.gethostname(),
            "error": str(e)
        }


@app.get("/items")
def get_items():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM items ORDER BY id DESC")
        items = cur.fetchall()
        cur.close()
        conn.close()
        return {"items": list(items), "count": len(items)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/items")
def create_item(name: str):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO items (name) VALUES (%s) RETURNING *",
            (name,)
        )
        item = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return {"message": "item created", "item": dict(item)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/items/{item_id}")
def get_item(item_id: int):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM items WHERE id = %s", (item_id,))
        item = cur.fetchone()
        cur.close()
        conn.close()
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        return dict(item)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/items/{item_id}")
def delete_item(item_id: int):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(
            "DELETE FROM items WHERE id = %s RETURNING *",
            (item_id,)
        )
        item = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        return {"message": "item deleted", "item": dict(item)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


Instrumentator().instrument(app).expose(app)