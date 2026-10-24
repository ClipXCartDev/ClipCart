FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# The derive worker is the only thing that needs an encoder, so ffmpeg is
# installed in its own stage rather than bloating the API image with it.
FROM base AS worker
RUN apt-get update  && apt-get install -y --no-install-recommends ffmpeg  && rm -rf /var/lib/apt/lists/*
CMD ["python", "-m", "app.worker.derive"]
