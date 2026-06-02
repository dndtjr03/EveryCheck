# Alembic 마이그레이션 가이드

EveryCheck 백엔드는 DB 스키마 변경을 **Alembic**으로 관리합니다.
`create_tables.py`(`Base.metadata.create_all()`)는 초기 셋업/테스트용으로만 사용하고,
실제 스키마 변경은 항상 마이그레이션 리비전을 통해 적용하세요.

## 사전 준비

```powershell
# backend/ 디렉터리에서 실행
venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

DB URL은 다음 순서로 해석됩니다:
1. `config.get_settings().database_url` (있으면)
2. 프로젝트 루트 `.env`의 `DATABASE_URL`
3. 쉘 환경변수 `DATABASE_URL`

## 자주 쓰는 명령 (모두 `backend/`에서)

```powershell
# 1) 현재 스키마를 기준으로 첫 리비전 생성 (autogenerate)
alembic revision --autogenerate -m "init schema baseline"

# 2) 최신 리비전까지 업그레이드
alembic upgrade head

# 3) 한 단계 다운그레이드
alembic downgrade -1

# 4) 현재 적용된 리비전 확인
alembic current

# 5) 히스토리 확인
alembic history --verbose
```

## 새 모델/컬럼을 추가했을 때

1. `models.py` 수정 후 저장.
2. `alembic revision --autogenerate -m "add xxx column"` 실행.
3. `alembic/versions/`에 생성된 파일을 **반드시 코드 리뷰** — autogenerate가
   놓치는 변경(컬럼명 RENAME, 데이터 마이그레이션 등)이 있는지 확인.
4. `alembic upgrade head`로 로컬 검증 → 커밋 → PR.

## 주의

- `env.py`는 `compare_type=True`, `compare_server_default=True`로 설정되어 있어
  컬럼 타입/기본값 변경도 감지합니다.
- 운영 DB에서는 반드시 백업 후 `alembic upgrade head`를 적용하세요.
- 기존 `create_tables.py`는 alembic 도입 이후에도 한동안 공존합니다.
  신규 환경에서는 `alembic upgrade head`만으로 충분합니다.
