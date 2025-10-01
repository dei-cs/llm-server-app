#!/bin/bash

##########################################################################
# ** Remove the following line if you have PATH issues on macOS **
# export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
##########################################################################

set -e  # Exit on error

echo "🚀 Starting LLM Server Application..."

# Load environment variables from .env
if [ -f .env ]; then
    # Source the .env file properly, removing comments and empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        # Remove Windows line endings (CRLF -> LF)
        line=$(echo "$line" | tr -d '\r')
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        # Remove inline comments
        line=$(echo "$line" | sed 's/#.*$//')
        # Trim whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Skip if line is empty after processing
        if [[ -z "$line" ]]; then
            continue
        fi
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
        # Convert Docker timestamp to Unix timestamp (cross-platform)
        IMAGE_DATE=$(echo "$IMAGE_CREATED" | cut -d'.' -f1 | sed 's/T/ /')
        if command -v gdate > /dev/null 2>&1; then
            # Use GNU date if available (macOS with coreutils)
            IMAGE_TIMESTAMP=$(gdate -d "$IMAGE_DATE" "+%s" 2> /dev/null || echo "0")
        elif date --version > /dev/null 2>&1; then
            # GNU date (Linux/Windows Git Bash)
            IMAGE_TIMESTAMP=$(date -d "$IMAGE_DATE" "+%s" 2> /dev/null || echo "0")
        else
            # BSD date (macOS)
            IMAGE_TIMESTAMP=$(date -j -f "%Y-%m-%d %H:%M:%S" "$IMAGE_DATE" "+%s" 2> /dev/null || echo "0")
        fi
        
        # Get file modification timestamps (cross-platform)
        if stat --version > /dev/null 2>&1; then
            # GNU stat (Linux/Windows Git Bash)
            APP_PY_TIMESTAMP=$(stat -c "%Y" api/app.py 2> /dev/null || echo "0")
            DOCKERFILE_TIMESTAMP=$(stat -c "%Y" api/Dockerfile 2> /dev/null || echo "0")
        else
            # BSD stat (macOS)
            APP_PY_TIMESTAMP=$(stat -f "%m" api/app.py 2> /dev/null || echo "0")
            DOCKERFILE_TIMESTAMP=$(stat -f "%m" api/Dockerfile 2> /dev/null || echo "0")
        fi
        
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

