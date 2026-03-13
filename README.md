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
