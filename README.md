## DOCKER (MANUAL)

### Bring container UP
docker compose up -d

### On change, rebuild
docker compose up -d --build

### Bring container DOWN
docker compose down

### Bring container DOWN and wipe volume cache
docker compose down -v



## OLLAMA

### Pull model
docker compose exec ollama ollama pull gemma3:1b

### See whats installed/pulled ATM
docker compose exec ollama ollama list



## SMOKE TESTS

### Chat inside the container
docker compose exec ollama ollama run gemma2:latest

### Health
curl http://localhost:3001/healthz

### Chat through API (default enforced to gemma2:latest)
curl -N -X POST http://localhost:3001/v1/chat \
  -H "Authorization: Bearer dev123" \
  -H "Content-Type: application/json" \
  -d '{
  "model": "gemma2:latest",
    "stream": true,
    "messages": [
      {"role":"system","content":"You are concise."},
      {"role":"user","content":"Say hi in 5 words."}
    ]
  }'