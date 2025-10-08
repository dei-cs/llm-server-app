FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn[standard] httpx pydantic-settings
COPY . .
CMD ["uvicorn", "src.api.app:app", "--host", "0.0.0.0", "--port", "3001"]
