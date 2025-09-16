## DOCKER

### Bring container UP
docker compose up -d
* On changes, build and force recreate
docker compose build api
docker compose up -d --no-deps --force-recreate api

### Bring container DOWN
docker compose down

### Bring container DOWN and wipe volume cache
docker compose down -v



## OLLAMA

### See whats installed
docker compose exec ollama ollama list

### Pull model
docker compose exec ollama ollama pull gemma2:latest
* When this is done, the model should be ready for use



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