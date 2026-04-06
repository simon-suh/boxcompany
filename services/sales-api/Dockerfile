FROM python:3.12-slim

WORKDIR /app

# Install dependencies first (cached layer — only rebuilds if requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the port FastAPI runs on
EXPOSE 3001

# Start the API server
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3001", "--reload"]
