"""헬스체크 라우터."""

from fastapi import APIRouter, Request, Response, status

from core.healthchecks import check_celery_workers, check_database, check_redis
from core.rate_limit import limiter

router = APIRouter()


@router.get(
    "/health",
    summary="헬스체크·준비 상태",
    description=(
        "프로세스·DB·Redis·Celery 워커 상태를 반환합니다. "
        "DB 연결 실패 시 503을 반환하며, Docker/K8s 헬스 프로브에 사용할 수 있습니다."
    ),
)
@limiter.limit("120/minute")
def health_check(request: Request, response: Response) -> dict:
    ok_db, err_db = check_database()
    ok_redis, err_redis = check_redis()
    ok_celery, err_celery, ping = check_celery_workers()

    body: dict = {
        "status": "healthy",
        "service": "dabadrim-teogeo",
        "checks": {
            "database": {"ok": ok_db, "error": err_db},
            "redis": {"ok": ok_redis, "error": err_redis},
            "celery_workers": {
                "ok": ok_celery,
                "error": err_celery,
                "workers": list(ping.keys()) if ping else [],
            },
        },
    }

    if not ok_db:
        body["status"] = "unhealthy"
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return body

    if not ok_redis or not ok_celery:
        body["status"] = "degraded"

    return body
