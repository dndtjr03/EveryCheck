"""Celery 애플리케이션 인스턴스 (Redis 브로커, AI 분석 비동기 태스크용)."""

import os

from celery import Celery

broker_url = os.getenv("CELERY_BROKER_URL", "redis://localhost:6379/0")
result_backend = os.getenv("CELERY_RESULT_BACKEND", broker_url)

celery_app = Celery(
    "teogeo",
    broker=broker_url,
    backend=result_backend,
    include=["worker"],
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
)
