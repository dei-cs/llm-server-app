import os, json
from typing import List, Literal
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import httpx

APP_API_KEY = os.getenv("APP_API_KEY")
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL")
ALLOWED_ORIGINS = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",")]
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
# When true, ignore client-provided model and always use DEFAULT_MODEL
ENFORCE_DEFAULT_MODEL = os.getenv("ENFORCE_DEFAULT_MODEL", "false").lower() == "true"

app = FastAPI(title="LLM Gateway")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if ALLOWED_ORIGINS == ["*"] else ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def check_auth(request: Request):
    auth = request.headers.get("authorization", "")
    if not APP_API_KEY:
        return  # no auth configured
    if auth != f"Bearer {APP_API_KEY}":
        raise HTTPException(status_code=401, detail="Unauthorized")

@app.get("/healthz")
async def healthz():
    return {"ok": True}

class ChatMessage(dict):
    role: Literal["system","user","assistant"]
    content: str

@app.post("/v1/chat")
async def chat(request: Request):
    check_auth(request)
    body = await request.json()
    model = DEFAULT_MODEL if ENFORCE_DEFAULT_MODEL else body.get("model", DEFAULT_MODEL)
    messages: List[ChatMessage] = body.get("messages", [])
    stream = bool(body.get("stream", True))

    if not messages:
        raise HTTPException(400, "messages required")

    payload = {
        "model": model,
        "messages": messages,
        "stream": stream,
    }

    client_timeout = httpx.Timeout(60.0, connect=10.0, read=60.0, write=60.0)
    client = httpx.AsyncClient(timeout=client_timeout)

    async def gen_stream():
        try:
            async with client.stream("POST", f"{OLLAMA_URL}/api/chat", json=payload) as r:
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if not line:
                        continue
                    # passthrough Ollama JSON lines as-is
                    yield (line + "\n").encode("utf-8")
        except httpx.HTTPError as e:
            yield json.dumps({"error": str(e)}).encode("utf-8")
        finally:
            await client.aclose()

    if stream:
        return StreamingResponse(gen_stream(), media_type="application/x-ndjson")

    # non-streaming: just relay JSON once
    try:
        r = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
        data = r.json()
        return JSONResponse(data, status_code=r.status_code)
    finally:
        await client.aclose()
