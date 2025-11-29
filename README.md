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
docker compose exec ollama ollama pull llama3.2:1b
docker compose exec ollama ollama pull all-minilm:22m

### See whats installed/pulled ATM
docker compose exec ollama ollama list



## SMOKE TESTS

### Chat inside the container
docker compose exec ollama ollama run llama3.2:1b

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



  ## EMBEDDING
  curl -X POST "http://localhost:11434/api/embed" -H "Content-Type: application/json" -d '{"model": "embeddinggemma:300m", "input": ["First sentence", "Second sentence", "Third sentence"]}'