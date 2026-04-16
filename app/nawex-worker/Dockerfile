# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
RUN useradd --no-create-home --uid 10001 --shell /usr/sbin/nologin nawex
COPY worker.py .
USER 10001:10001
CMD ["python", "worker.py"]
