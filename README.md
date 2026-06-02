# 다봐드림 - 임대차 원상복구 비용 분석 백엔드

임대차 원상복구 비용 분석 서비스 「다봐드림」의 백엔드 인프라 예시 구현입니다.  
FastAPI, PostgreSQL, SQLAlchemy, Docker, AWS S3, JWT 인증을 활용한 기본 구조를 제공합니다.

## 기술 스택

- **웹 프레임워크**: FastAPI
- **DB**: PostgreSQL
- **ORM**: SQLAlchemy
- **인증**: JWT (python-jose, passlib)
- **스토리지**: AWS S3 (boto3)
- **컨테이너**: Docker, docker-compose

## 주요 기능 개요

- **JWT 기반 사용자 인증**
- **임대차 계약 정보(RealEstate) 관리**
- **손상 이미지(DamageImages) 업로드**
  - 업로드 시 **SHA-256 해시값 계산 및 DB 저장** (무결성 검증용)
  - AWS S3에 이미지 업로드 후 URL 저장
- **수리비/감가상각 계산(RepairEstimates)**
  - 국토부 가이드라인(벽지/장판 내구연수 10년 기준)을 반영한
  - 공식: `임차인 부담비용 = 총 수리비 * (1 - 경과연수/내용연수)`

## 로컬 개발 환경 실행 방법

### 1. 파이썬 가상환경 생성 (선택)

```bash
python -m venv .venv
.venv\Scripts\activate  # Windows PowerShell
```

### 2. 패키지 설치

```bash
pip install -r requirements.txt
```

### 3. 환경 변수 설정 (예시)

PowerShell 기준:

```powershell
$env:DATABASE_URL = "postgresql+psycopg2://app:app@localhost:5432/teogeo"
$env:JWT_SECRET_KEY = "change-me-in-production"
$env:JWT_ALGORITHM = "HS256"
$env:ACCESS_TOKEN_EXPIRE_MINUTES = "60"
$env:AWS_REGION = "ap-northeast-2"
$env:S3_BUCKET_NAME = "your-s3-bucket-name"
```

### 4. 애플리케이션 실행

```bash
uvicorn main:app --reload
```

브라우저에서 다음 주소로 접속해 자동 문서를 확인할 수 있습니다.

- `http://localhost:8000/docs` (Swagger UI)
- `http://localhost:8000/redoc`

## Docker / docker-compose 실행

### 1. Docker Desktop 설치

- Windows / macOS용 Docker Desktop 다운로드: [Docker Desktop 다운로드 페이지](https://www.docker.com/products/docker-desktop/)

Docker Desktop 설치 후, 애플리케이션을 실행하여 Docker 엔진이 켜져 있는지 확인합니다.

### 2. 환경 변수 파일(.env) 준비

프로젝트 루트(`teogeo`)에서 다음 명령을 실행하거나 파일 탐색기에서 복사합니다.

```bash
cp .env.example .env  # Windows PowerShell에서는 copy .env.example .env 사용 가능
```

그 후, 생성된 `.env` 파일을 열어 다음 값을 실제 환경에 맞게 수정합니다.

- `DB_PASSWORD`: 로컬/테스트용 PostgreSQL 비밀번호
- `JWT_SECRET_KEY`: 충분히 긴 랜덤 문자열 (운영 환경에서 반드시 강력한 값 사용)
- `S3_BUCKET_NAME`: 사용할 S3 버킷 이름

> ⚠️ **주의:** 실제 비밀번호, 시크릿 키 등이 담긴 `.env` 파일은 절대 GitHub 등 원격 저장소에 커밋하지 마세요.

### 3. Docker 이미지 빌드 및 서비스 실행

```bash
docker-compose up --build
```

기본 설정:

- FastAPI 앱: `http://localhost:8000`
- PostgreSQL: `localhost:5432` (user: `app`, password: `app`, db: `teogeo`)

### 4. API 명세 확인

- 브라우저에서 `http://localhost:8000/docs` 에 접속하면 Swagger UI 기반의 **API 명세 및 테스트 콘솔**을 확인할 수 있습니다.
- `Authorize` 버튼을 통해 발급받은 JWT 토큰을 입력하면 인증이 필요한 엔드포인트도 바로 테스트할 수 있습니다.

## 주요 환경 변수 정리

- **DATABASE_URL**: SQLAlchemy용 DB 접속 URL  
  예시: `postgresql+psycopg2://app:app@db:5432/teogeo`
- **JWT_SECRET_KEY**: JWT 서명용 비밀키 (반드시 운영 환경에서 강한 랜덤값으로 교체)
- **JWT_ALGORITHM**: JWT 알고리즘 (기본: HS256)
- **ACCESS_TOKEN_EXPIRE_MINUTES**: 액세스 토큰 만료 시간(분)
- **AWS_REGION**: S3 리전 (예: `ap-northeast-2`)
- **S3_BUCKET_NAME**: 이미지 업로드 대상 S3 버킷 이름

> ⚠️ **보안 경고:** 실제 서비스 환경에서 사용하는 비밀번호, 토큰, 시크릿 키 등이 담긴 `.env` 파일은 절대 Git 저장소(특히 GitHub)에 올리지 말고, 팀 내에서 별도 안전한 방식(예: 비밀 관리자, 암호화된 채널)을 통해 공유해야 합니다.

## 디렉터리/파일 구조

- `main.py` : FastAPI 엔드포인트 및 JWT 인증 로직
- `models.py` : SQLAlchemy ORM 모델 정의
- `database.py` : DB 연결 및 세션 관리
- `schemas.py` : Pydantic 스키마 정의
- `utils.py` : 해시 계산, 감가상각 계산, S3 업로드 유틸
- `requirements.txt` : 파이썬 의존성
- `Dockerfile` : FastAPI 앱 컨테이너 빌드 설정
- `docker-compose.yml` : FastAPI + PostgreSQL 통합 실행 설정

이 스켈레톤을 기반으로 실제 서비스 요구사항에 맞게 엔드포인트/비즈니스 로직을 확장하면 됩니다.

--------------------------------------
# EveryCheck
2026년 1학기 기업연계프로젝트(캡스톤디자인경진대회) 1조 모바일 어플리케이션. 
주거 관련 분쟁 조언 AI

# 다봐드림 🏠🔍
> AI 기반 임대차 원상복구 분쟁 조절 시스템

[![Python](https://img.shields.io/badge/Python-3.10+-blue)](https://python.org)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-green)](https://fastapi.tiangolo.com)
[![React Native](https://img.shields.io/badge/React_Native-Expo-purple)](https://expo.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## 📌 프로젝트 소개
세입자가 입주·퇴거 시 촬영한 사진을 AI가 비교 분석하여 파손을 자동 탐지하고,  
국토교통부 가이드라인 및 판례를 근거로 과실 비율과 수리비 분담액을 산출하는 모바일 서비스입니다.

---

## 👥 팀원

| 이름 | 역할 | GitHub |
|------|------|--------|
| 이웅석 | 팀장 / 데이터 수집 · 법리 분석 · 판례 벡터 DB | - |
| 조효민 | 백엔드 · Docker 인프라 | - |
| 심우재 | AI 모델 개발 (YOLOv8, LLM, RAG) | - |
| 김수호 | 모바일 앱 프론트엔드 (React Native) | - |


---

## 🛠 기술 스택

| 분야 | 기술 |
|------|------|
| AI | Python 3.10, YOLOv8, PyTorch, LangChain, ChromaDB |
| 백엔드 | FastAPI, PostgreSQL, Docker, Nginx |
| 프론트엔드 | React Native, Expo |
| 데이터 | pdfplumber, sentence-transformers, Roboflow |

---

## 📁 프로젝트 구조
```
dabwadream/
├── backend/          # FastAPI 서버
├── ai/               # AI 모델 (YOLOv8, LLM)
├── mobile/           # React Native 앱
├── data/             # 판례·데이터셋
│   ├── raw/          # 원본 PDF·TXT
│   ├── processed/    # 가공 데이터
│   ├── labeled/      # 라벨링 데이터셋
│   └── chroma_db/    # 벡터 DB
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## 🚀 시작하기
```bash
# 1. 레포 클론
git clone https://github.com/팀레포주소.git
cd dabwadream

# 2. 환경변수 설정
cp .env.example .env
# .env 파일에 API 키 입력

# 3. Docker 실행
docker-compose up --build
```

> Swagger UI: http://localhost:8000/docs

---

## 🌿 브랜치 전략

### 브랜치 구조
```
main         ← 최종 배포 브랜치 (직접 push 금지)
develop      ← 통합 개발 브랜치 (PR을 통해서만 병합)
feature/*    ← 기능 개발
fix/*        ← 버그 수정
hotfix/*     ← 긴급 수정 (main에서 분기)
```

### 브랜치 네이밍 규칙
```
feature/담당분야-작업내용
feature/data-판례수집
feature/backend-jwt인증
feature/ai-yolo학습
feature/frontend-로그인화면

fix/버그내용
fix/api-응답오류

hotfix/긴급내용
hotfix/배포환경-크래시수정
```

### 브랜치 작업 흐름
```bash
# 1. develop에서 새 브랜치 생성
git checkout develop
git pull origin develop
git checkout -b feature/data-판례수집

# 2. 작업 후 커밋
git add .
git commit -m "feat: 판례 50건 파싱 및 전처리 완료"

# 3. develop으로 PR 생성 (직접 merge 금지)
git push origin feature/data-판례수집
# GitHub에서 PR 생성 → 팀장 리뷰 후 merge
```

### ⚠️ 브랜치 규칙
- `main`, `develop`에 직접 push **금지**
- PR은 최소 **1명 리뷰** 후 merge
- merge 후 feature 브랜치 **삭제**
- 작업 전 반드시 `git pull origin develop` 먼저 실행

---

## ✏️ 커밋 메시지 규칙
```
타입: 작업 내용 (50자 이내)

예시:
feat: 판례 50건 ChromaDB 벡터 임베딩 완료
feat: YOLOv8 파손 탐지 모델 파인튜닝
fix: 이미지 업로드 API 500 오류 수정
docs: README 브랜치 전략 추가
refactor: 판례 파싱 함수 리팩터링
test: 보증금 계산 API 단위 테스트 추가
chore: .gitignore 모델 파일 추가
```

| 타입 | 설명 |
|------|------|
| `feat` | 새로운 기능 추가 |
| `fix` | 버그 수정 |
| `docs` | 문서 수정 |
| `refactor` | 코드 리팩터링 |
| `test` | 테스트 코드 |
| `chore` | 빌드·설정 변경 |
| `style` | 코드 포맷팅 |

---

## 🔐 환경변수 목록

`.env.example` 참고:
```
DATABASE_URL=
SECRET_KEY=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```

> ⚠️ `.env` 파일은 절대 커밋하지 마세요!

---

## 📅 개발 일정

| 기간 | 내용 |
|------|------|
| 3월 | 환경 설정, 데이터 수집, API 기반 구축 |
| 4월 | AI 모델 학습, 앱 화면 개발 |
| 5월 | 통합 테스트, 최종 마무리 |
| **5월 27일** | **1학기 최종 제출** |
| 여름방학~2학기 | 고도화 및 추가 기능 개발 |

---

## 📄 라이선스
MIT License © 2026 다봐드림 팀
