import os, json
import logging
from typing import List, Literal
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import httpx

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [LLM SERVICE] - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

APP_API_KEY = os.getenv("APP_API_KEY")
DEFAULT_MODEL = os.getenv("DEFAULT_MODEL")
DEFAULT_EMBEDDING_MODEL = os.getenv("DEFAULT_EMBEDDING_MODEL")
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
    
    logger.info(f"{'='*60}")
    logger.info(f"Chat request - Model: {model}, Messages: {len(messages)}, Stream: {stream}")

    if not messages:
        logger.error("No messages provided in request")
        raise HTTPException(400, "messages required")
    
    # Log first message preview
    if messages:
        first_msg = messages[0]
        preview = str(first_msg.get('content', ''))[:100]
        logger.info(f"First message preview: {preview}...")

    payload = {
        "model": model,
        "messages": messages,
        "stream": stream,
    }

    client_timeout = httpx.Timeout(60.0, connect=10.0, read=60.0, write=60.0)
    client = httpx.AsyncClient(timeout=client_timeout)

    async def gen_stream():
        logger.info(f"Connecting to Ollama at {OLLAMA_URL}/api/chat")
        chunk_count = 0
        try:
            async with client.stream("POST", f"{OLLAMA_URL}/api/chat", json=payload) as r:
                r.raise_for_status()
                logger.info(f"✓ Ollama connection established, streaming response...")
                async for line in r.aiter_lines():
                    if not line:
                        continue
                    chunk_count += 1
                    # passthrough Ollama JSON lines as-is
                    yield (line + "\n").encode("utf-8")
                logger.info(f"✓ Stream complete - sent {chunk_count} chunks")
                logger.info(f"{'='*60}")
        except httpx.HTTPError as e:
            logger.error(f"✗ Ollama HTTP error: {e}")
            yield json.dumps({"error": str(e)}).encode("utf-8")
        finally:
            await client.aclose()

    if stream:
        return StreamingResponse(gen_stream(), media_type="application/x-ndjson")

    # non-streaming: just relay JSON once
    logger.info(f"Making non-streaming request to Ollama")
    try:
        r = await client.post(f"{OLLAMA_URL}/api/chat", json=payload)
        ollama_data = r.json()
        logger.info(f"✓ Received non-streaming response (status: {r.status_code})")
        
        # Transform Ollama format to OpenAI format
        # Ollama: {"message": {"content": "..."}}
        # OpenAI: {"choices": [{"message": {"content": "..."}}]}
        openai_format = {
            "choices": [
                {
                    "message": ollama_data.get("message", {}),
                    "finish_reason": "stop"
                }
            ],
            "model": model
        }
        logger.info(f"✓ Transformed to OpenAI format")
        logger.info(f"{'='*60}")
        return JSONResponse(openai_format, status_code=r.status_code)
    except Exception as e:
        logger.error(f"✗ Error in non-streaming request: {e}")
        raise
    finally:
        await client.aclose()

