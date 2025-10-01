#!/bin/bash

set -e  # Exit on error

# Ensure Docker is in PATH (macOS Docker Desktop)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

echo "🚀 Starting LLM Server Application..."

# Load environment variables from .env
if [ -f .env ]; then
    # Source the .env file properly, removing comments and empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        # Remove inline comments
        line=$(echo "$line" | sed 's/#.*$//')
        # Export the variable
        export "$line"
    done < .env
    echo "✅ Loaded environment variables from .env"
    echo "   Model: $DEFAULT_MODEL"
else
    echo "❌ Error: .env file not found"
    exit 1
fi

# Check if API code has changed or if API image doesn't exist
echo "🔍 Checking if API rebuild is needed..."
API_IMAGE_EXISTS=$(docker images -q llm-server-app-api 2> /dev/null)

if [ -z "$API_IMAGE_EXISTS" ]; then
    echo "📦 API image not found, building..."
    REBUILD_API=true
else
    # Check if app.py or Dockerfile has been modified more recently than the image
    IMAGE_CREATED=$(docker inspect -f '{{.Created}}' llm-server-app-api 2> /dev/null | head -1)
    if [ -n "$IMAGE_CREATED" ]; then
        IMAGE_TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo $IMAGE_CREATED | cut -d'.' -f1)" "+%s" 2> /dev/null || echo "0")
        APP_PY_TIMESTAMP=$(stat -f "%m" api/app.py 2> /dev/null || echo "0")
        DOCKERFILE_TIMESTAMP=$(stat -f "%m" api/Dockerfile 2> /dev/null || echo "0")
        
        if [ "$APP_PY_TIMESTAMP" -gt "$IMAGE_TIMESTAMP" ] || [ "$DOCKERFILE_TIMESTAMP" -gt "$IMAGE_TIMESTAMP" ]; then
            echo "🔄 API code changes detected, rebuilding..."
            REBUILD_API=true
        else
            echo "✅ API code unchanged, skipping rebuild"
            REBUILD_API=false
        fi
    else
        REBUILD_API=true
    fi
fi

# Rebuild API if needed
if [ "$REBUILD_API" = true ]; then
    docker compose build api
    echo "✅ API rebuilt successfully"
fi

# Start Docker Compose services
echo "🐳 Starting Docker containers..."
docker compose up -d

# Wait for Ollama service to be ready
echo "⏳ Waiting for Ollama service to be ready..."
until docker compose exec ollama ollama list > /dev/null 2>&1; do
    echo "   Waiting for Ollama..."
    sleep 2
done
echo "✅ Ollama service is ready"

# Pull the model specified in DEFAULT_MODEL
echo "📥 Pulling model: $DEFAULT_MODEL"
docker compose exec ollama ollama pull $DEFAULT_MODEL

if [ $? -eq 0 ]; then
    echo "✅ Model $DEFAULT_MODEL pulled successfully"
else
    echo "❌ Failed to pull model $DEFAULT_MODEL"
    exit 1
fi

# Restart the API service to ensure it's using the latest configuration
echo "🔄 Restarting API service to apply changes..."
docker compose restart api

# Wait for API to be ready
echo "⏳ Waiting for API service to be ready..."
sleep 3
until curl -s http://localhost:3001/healthz > /dev/null 2>&1; do
    echo "   Waiting for API..."
    sleep 2
done

echo "✅ API service is ready"
echo ""
echo "📍 API available at: http://localhost:3001"
echo "🤖 Model in use: $DEFAULT_MODEL"

