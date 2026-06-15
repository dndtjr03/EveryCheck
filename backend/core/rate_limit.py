"""SlowAPI 레이트 리미터 — 라우터 데코레이터에서 공통 참조."""

from slowapi import Limiter
from slowapi.util import get_remote_address

# 기본: 분당 20회. 라우터별로 `@limiter.limit("5/minute")` 등 오버라이드 가능.
limiter = Limiter(key_func=get_remote_address, default_limits=["20/minute"])
