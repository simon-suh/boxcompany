FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# No port exposed — this service has no REST API
# It runs as a pure Kafka consumer process

CMD ["python3", "main.py"]
