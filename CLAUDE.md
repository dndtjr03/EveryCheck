# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**다봐드림(EveryCheck)** — 임대차 퇴거 시 손상 이미지를 AI(Google Gemini)로 분석해 과실 비율·원상복구 비용을 자동 산출하는 모바일 + 백엔드 서비스.

- **Backend**: `backend/` — FastAPI (Python 3.11)
- **Frontend**: `Flutter/` — Flutter (Dart)
- **Infrastructure**: PostgreSQL 15, Redis, AWS S3, Celery, Nginx

---

## Commands

### Backend (FastAPI)

```powershell
# 가상환경 활성화 및 의존성 설치
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 로컬 실행 (backend/ 디렉터리에서)
uvicorn main:app --reload
# Swagger UI: http://localhost:8000/docs

# DB 마이그레이션
alembic revision --autogenerate -m "설명"
alembic upgrade head

# Celery 워커 실행 (별도 터미널)
celery -A celery_app worker --loglevel=info
```

```bash
# Docker Compose로 전체 스택 실행 (루트 디렉터리)
docker-compose up --build
```

### Frontend (Flutter)

```bash
# 의존성 설치
flutter pub get

# 개발 실행 (에뮬레이터/기기 필요)
flutter run

# 린트
flutter analyze

# 코드 포맷
dart format lib/

# 빌드
flutter build apk    # Android
flutter build ios    # iOS

# 단일 테스트 파일 실행
flutter test test/widget_test.dart
```

---

## Architecture

### Backend 레이어 구조

```
main.py (FastAPI 앱·엔드포인트)
  ├─ auth.py          — JWT 생성/검증, bcrypt 비밀번호 해싱
  ├─ models.py        — SQLAlchemy ORM (User, RealEstate, DamageImage, RepairEstimate)
  ├─ schemas.py       — Pydantic 요청/응답 스키마
  ├─ database.py      — DB 연결, 세션 팩토리
  ├─ utils.py         — S3 업로드, 파일 검증(MIME/SHA-256), 감가상각 계산
  ├─ worker.py        — Celery 비동기 AI 분석 태스크
  ├─ celery_app.py    — Celery 인스턴스 (broker: Redis)
  └─ security_audit.py — 민감 엔드포인트 감사 로그
```

**AI 분석 흐름**: 이미지 업로드 → S3 저장 → Celery 큐 → `analyze_image_task` → Gemini API 호출 → 감가상각 공식 적용 → `RepairEstimate` DB 업데이트 (상태: `pending → analyzing → completed/failed`)

**감가상각 공식** (국토교통부 가이드라인):
> 임차인 부담 = 총 수리비 × (1 - 경과연수 / 내용연수)

**보안 레이어**:
- SlowAPI 레이트 리밋 (기본 20/분, 로그인·분석 5/분)
- 파일 업로드: 10MB 제한, `.jpg/.jpeg/.png/.webp` 화이트리스트, python-magic MIME 검증
- Security Headers: `X-Content-Type-Options`, `X-Frame-Options`, CSP (Swagger UI 예외 처리)

### Frontend 레이어 구조

```
main.dart (MultiProvider 부트스트랩 + _AuthGate 조건부 라우팅)
  ├─ providers/
  │    ├─ AuthProvider     — 인증 상태 (unknown → authenticated/unauthenticated)
  │    └─ ContractProvider — 임대차 계약 목록 캐싱
  ├─ services/
  │    ├─ ApiService       — 싱글톤 HTTP 클라이언트 (토큰 자동 첨부)
  │    ├─ AuthService      — 회원가입/로그인 API
  │    ├─ ContractService  — 계약 CRUD API
  │    └─ AnalysisService  — AI 분석 요청 API
  ├─ screens/              — auth/, home/, contract/, analysis/
  ├─ models/               — Dart 데이터 모델
  └─ config/app_config.dart — API 베이스 URL, 토큰 키 상수
```

**라우팅**: Named Routes (`/login`, `/register`, `/home`). `_AuthGate`가 `AuthProvider` 상태를 감시해 자동 리다이렉트.

**토큰 저장**: `FlutterSecureStorage` (암호화). `ApiService`가 모든 요청에 `Authorization: Bearer` 헤더 자동 주입.

---

## Environment Setup

`.env.example`을 복사해 `.env` 생성 후 아래 변수를 채운다:

| 변수 | 설명 |
|------|------|
| `DATABASE_URL` | PostgreSQL 연결 문자열 |
| `JWT_SECRET_KEY` | HS256 서명 키 |
| `AWS_REGION` / `S3_BUCKET_NAME` | 이미지 저장소 |
| `GOOGLE_API_KEY` | Gemini API 키 |
| `REDIS_URL` | Celery 브로커 |
| `CORS_ORIGINS` | 허용할 Origin 목록 (쉼표 구분) |

Flutter API 엔드포인트는 `Flutter/lib/config/app_config.dart`에서 변경.

---

## Branch Strategy

| 브랜치 | 용도 |
|--------|------|
| `main` | 배포용 — 직접 push 금지, PR만 허용 |
| `develop` | 통합 개발 — PR을 통해서만 병합 |
| `feature/*` | 기능 개발 |
| `fix/*` | 버그 수정 |
| `hotfix/*` | 긴급 패치 |

커밋 메시지 예시: `feat: 손상 이미지 업로드 기능 추가`, `fix: JWT 만료 처리 오류 수정`
