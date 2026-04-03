"""민감 엔드포인트 접근 감사 로그 (/auth/token, /analyze 등).

표준 라이브러리 `logging` 패키지와 이름이 겹치지 않도록 security_audit.py 로 둔다.
"""

import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional

_audit_logger: Optional[logging.Logger] = None


def _get_log_path() -> Path:
    raw = os.getenv("SECURITY_LOG_PATH", "/var/log/teogeo/security_audit.log")
    return Path(raw)


def init_security_audit_logger() -> logging.Logger:
    """파일 로거를 한 번만 구성한다."""
    global _audit_logger
    if _audit_logger is not None:
        return _audit_logger

    log_path = _get_log_path()
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("teogeo.security_audit")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    handler = RotatingFileHandler(
        log_path,
        maxBytes=int(os.getenv("SECURITY_LOG_MAX_BYTES", str(10 * 1024 * 1024))),
        backupCount=int(os.getenv("SECURITY_LOG_BACKUP_COUNT", "5")),
        encoding="utf-8",
    )
    fmt = logging.Formatter(
        "%(asctime)s\t%(levelname)s\t%(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    )
    handler.setFormatter(fmt)
    logger.addHandler(handler)
    logger.propagate = False

    _audit_logger = logger
    return logger


def client_ip_from_request(request) -> str:
    """X-Forwarded-For 우선, 없으면 직접 연결 IP."""
    xff = request.headers.get("x-forwarded-for") or request.headers.get("X-Forwarded-For")
    if xff:
        return xff.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


def log_sensitive_endpoint_access(
    request,
    *,
    path: str,
    extra: str = "",
) -> None:
    """로그인·AI 분석 등 민감 경로 접근을 파일에 기록한다."""
    logger = init_security_audit_logger()
    ip = client_ip_from_request(request)
    ua = (request.headers.get("user-agent") or "").replace("\t", " ")[:500]
    method = request.method
    line = f"ip={ip}\tmethod={method}\tpath={path}\tuser_agent={ua}"
    if extra:
        line += f"\t{extra}"
    logger.info(line)
