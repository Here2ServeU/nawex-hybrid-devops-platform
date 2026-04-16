FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY worker.py .
RUN useradd --create-home --uid 10001 nawex
USER 10001:10001
CMD ["python", "worker.py"]
