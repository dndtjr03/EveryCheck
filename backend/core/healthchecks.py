"""DB/Redis/Celery 헬스체크 헬퍼."""

from typing import Optional

from sqlalchemy import text

from config import get_settings
from database import engine


def check_database() -> tuple[bool, Optional[str]]:
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return True, None
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def check_redis() -> tuple[bool, Optional[str]]:
    try:
        import redis

        url = get_settings().redis_url
        r = redis.from_url(url, socket_connect_timeout=3)
        r.ping()
        return True, None
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def check_celery_workers() -> tuple[bool, Optional[str], Optional[dict]]:
    try:
        from celery_app import celery_app

        insp = celery_app.control.inspect(timeout=3.0)
        if insp is None:
            return False, "inspect unavailable", None
        ping = insp.ping()
        if not ping:
            return False, "no worker responded to ping", None
        return True, None, ping
    except Exception as exc:  # noqa: BLE001
        return False, str(exc), None
