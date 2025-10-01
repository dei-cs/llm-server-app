## QUICK START (RECOMMENDED)

### Automated Startup Script
This script will start all services, pull the configured model, and ensure everything is ready.

```bash
# Make the script executable (first time only)
chmod +x startup.sh

# Run the startup script
./startup.sh
```

The script will:
1. Load environment variables from `.env`
2. **Auto-detect if API code has changed** and rebuild if needed
3. Start Docker containers
4. Wait for Ollama to be ready
5. Pull the model specified in `DEFAULT_MODEL` (from `.env`)
6. Restart API service to apply any changes
7. Verify API is responding

**Use cases:**
- ✅ **Change model:** Edit `DEFAULT_MODEL` in `.env` and run `./startup.sh`
- ✅ **Change ENV variables:** Edit `.env` and run `./startup.sh`
- ✅ **Modify API code:** Edit `api/app.py` and run `./startup.sh` (auto-rebuilds)
- ✅ **Fresh start:** Just run `./startup.sh` anytime!


## DOCKER (MANUAL)

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