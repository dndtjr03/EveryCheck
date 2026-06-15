"""HTTP 미들웨어 — 감사 로그·보안 헤더."""

from fastapi import FastAPI, Request

from config import get_settings
from security_audit import log_sensitive_endpoint_access


def install_middlewares(app: FastAPI) -> None:
    """FastAPI 앱에 감사 로그·보안 헤더 미들웨어를 등록한다."""

    settings = get_settings()

    @app.middleware("http")
    async def _sensitive_endpoint_audit(request: Request, call_next):
        path = request.url.path
        if request.method == "POST" and path in ("/auth/token", "/analyze"):
            try:
                log_sensitive_endpoint_access(request, path=path)
            except OSError:
                pass
        return await call_next(request)

    @app.middleware("http")
    async def _security_headers(request: Request, call_next):
        response = await call_next(request)
        path = request.url.path
        is_docs = path == "/docs" or path.startswith("/docs/")

        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        if not is_docs:
            response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("X-XSS-Protection", "1; mode=block")
        response.headers.setdefault(
            "Referrer-Policy", "strict-origin-when-cross-origin"
        )
        response.headers.setdefault(
            "Permissions-Policy",
            "geolocation=(), microphone=(), camera=(), payment=()",
        )
        if is_docs:
            response.headers["Content-Security-Policy"] = (
                "default-src 'self'; "
                "script-src 'self' 'unsafe-inline'; "
                "style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data:;"
            )
        else:
            response.headers.setdefault(
                "Content-Security-Policy",
                "default-src 'none'; frame-ancestors 'none'",
            )
        if settings.enable_hsts:
            response.headers.setdefault(
                "Strict-Transport-Security",
                "max-age=31536000; includeSubDomains",
            )
        return response
