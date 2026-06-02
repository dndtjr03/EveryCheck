# 다봐드림(EveryCheck) — 세션 컨텍스트

> 이 파일을 새 채팅 첫 메시지에 첨부하면 이전 작업 흐름을 이어받을 수 있습니다.
> 작성일: 2026-06-02

---

## 프로젝트 개요

임대차 퇴거 시 손상 이미지를 AI(Gemini Vision)로 분석해 과실 비율·원상복구 비용을 자동 산출하는 모바일+백엔드 서비스.

- **발표일**: 2026-06-04
- **Backend**: `backend/` — FastAPI (Python 3.11), venv: `EveryCheck/venv` (Python 3.11.9)
- **Frontend**: `Flutter/` — Flutter (Dart)
- **DB**: Docker PostgreSQL 15 (로컬), Redis

---

## 작업 환경 규칙 (필독)

1. **작업 경로**: `C:\Users\lee01\Desktop\WKU-Class\EveryCheck_26Y\EveryCheck` (`.claude/worktrees` 아님)
2. **백엔드 직접 실행 금지**: 명령어만 제공, 실행은 사용자가 직접
3. **venv 위치**: `EveryCheck\venv\Scripts\python.exe` (Python 3.11.9)
4. **백엔드 실행 시 필수**: `$env:PYTHONUTF8 = "1"` (한글 .env 인코딩 오류 방지)

---

## 현재 배포 구조

```
폰 (APK) ──HTTPS──▶ Cloudflare Tunnel ──▶ localhost:8000 (uvicorn) ──▶ Docker DB/Redis
```

- `cloudflared` 설치 경로:  
  `C:\Users\lee01\AppData\Local\Microsoft\WinGet\Packages\Cloudflare.cloudflared_Microsoft.Winget.Source_8wekyb3d8bbwe\cloudflared.exe`
- 현재 방식: **trycloudflare 임시 URL** (매번 재시작 시 URL 변경됨)
- 임시 URL 사용 시 APK를 매번 재빌드해야 함

### 시연 실행 스크립트
- `C:\Users\lee01\Desktop\start-demo.bat` — 백엔드 + cloudflared 동시 실행
- `C:\Users\lee01\Desktop\rebuild-apk-with-url.bat` — URL 입력받아 APK 재빌드+설치

---

## 주요 수정 파일 현황

### Backend

| 파일 | 주요 내용 |
|------|----------|
| `backend/analysis_proxy_router.py` | Gemini 4개 프롬프트 튜닝, 2장 비교 엔드포인트, RAG mix |
| `backend/rag/chunking.py` | `chunk_repair_price()`, `chunk_static_laws()`, 23개 동의어 매핑 |
| `backend/rag/ingest.py` | `--ingest-repair-prices`, `--ingest-static-laws` CLI 옵션 |
| `backend/main.py` | RAG warmup startup hook, `/photos/upload-single` 엔드포인트 |
| `backend/data/repair_price/repair_unit_prices.json` | LH 표준단가 71개 항목 |
| `backend/data/static_laws/rental_core.json` | 핵심 임대차 법령 10조문 |

#### RAG 구성 (총 ~146 chunks)
- `repair_price`: 71개 (LH 표준단가)
- `precedent`: 51개 (판례)
- `interpretation`: 14개 (해석례)
- `law`: 10개 (민법/주임법/상임법)

#### `_RAG_MIX` 설정
```python
_RAG_MIX = [("repair_price", 1), ("precedent", 2), ("law", 1), ("interpretation", 1)]
_CHUNK_PREVIEW_CHARS = 350
```

### Flutter

| 파일 | 주요 내용 |
|------|----------|
| `Flutter/lib/services/pdf_report_service.dart` | NanumGothic TTF 번들 로드 (CDN 제거) |
| `Flutter/lib/services/api_service.dart` | `fileContentType` 파라미터 추가 |
| `Flutter/lib/services/photo_upload_service.dart` | `uploadSingle()` S3 업로드 메서드 |
| `Flutter/lib/services/analysis_proxy_service.dart` | `analyzePhotoWithBaseline()` (2장 비교) |
| `Flutter/lib/screens/analysis/analysis_chat_screen.dart` | baseline 비교 분기, is_new 기반 비용 합산 |
| `Flutter/lib/local/local_db.dart` | DB v2, `s3_url` 컬럼 추가 |
| `Flutter/assets/fonts/` | NanumGothic-Regular.ttf, NanumGothic-Bold.ttf |
| `Flutter/pubspec.yaml` | 폰트 등록, `http_parser: ^4.0.2` |

---

## 엔드포인트 목록

| 엔드포인트 | 설명 |
|-----------|------|
| `POST /auth/token` | 로그인 |
| `POST /proxy/analyze-photo` | 단일 이미지 분석 |
| `POST /proxy/analyze-with-baseline` | 2장 비교 분석 (move_out + move_in_images) |
| `POST /photos/upload-single` | S3 단건 업로드 → `{"s3_url": "..."}` |
| `GET /health` | 헬스체크 |

---

## 미완료 작업

### 우선순위 높음 (발표 전)
- [ ] **Cloudflare Named Tunnel + 고정 도메인** 설정 (학교 무료계정 활용 예정)
  - 고정 URL 확보 시 APK 재빌드 마지막 1회로 끝남
  - 단계: 도메인 확보 → Cloudflare DNS → `cloudflared tunnel create` → `config.yml` → APK 재빌드
- [ ] **시연 영상 녹화** (백업용 1분 30초)
- [ ] **PPT 슬라이드 8/9/10** 실제 앱 스크린샷으로 교체

### 우선순위 낮음 (발표 후)
- [ ] AWS RDS 전환 (조효민 계정 필요: RDS endpoint, user, pw, db명)
- [ ] `.venv` 충돌 정리 (`backend/.venv`는 py314 기반 → 사용 안 함, `venv`가 정상)
- [ ] RAG "원원" 표시 버그 수정

---

## 시드 계정

```
이메일  : seed_user@everycheck.com
비밀번호 : TestSeed!123
```

---

## 백엔드 실행 명령 (참고용)

```powershell
# Docker
cd C:\Users\lee01\Desktop\WKU-Class\EveryCheck_26Y\EveryCheck
docker-compose up -d

# 백엔드
cd backend
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
..\venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000

# Cloudflare Tunnel
cloudflared tunnel --url http://localhost:8000 --no-autoupdate
```

---

## Cloudflare Named Tunnel 설정 (다음 작업)

현재 trycloudflare 임시 URL → 고정 URL로 전환 예정

**단계 요약:**
1. 도메인 확보 (GitHub Student Pack → Namecheap .me 무료 or 구매)
2. Cloudflare에 도메인 추가 + 네임서버 변경 (24~48시간 전파)
3. `cloudflared tunnel login`
4. `cloudflared tunnel create dabadrim`
5. `cloudflared tunnel route dns dabadrim api.<도메인>`
6. `%USERPROFILE%\.cloudflared\config.yml` 작성
7. `cloudflared tunnel run dabadrim`
8. 고정 URL로 APK 최종 재빌드 (이후 재빌드 불필요)

**cloudflared 실행 경로:**
```
C:\Users\lee01\AppData\Local\Microsoft\WinGet\Packages\Cloudflare.cloudflared_Microsoft.Winget.Source_8wekyb3d8bbwe\cloudflared.exe
```
