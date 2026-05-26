"""법제처 OpenAPI 기반 RAG 모듈.

구성:
  - lawgokr_client : 법제처 API 호출 (검색·본문)
  - chunking       : 소스별 청킹 (법령은 조 단위, 판례는 판시사항+판결요지)
  - chroma_index   : ChromaDB 추상화 (한국어 임베딩 모델 자동 로드)
  - ingest         : raw 수집 → chunk → embed → ChromaDB 적재 통합 파이프라인

환경 변수 (.env):
  LAW_GO_KR_OC          : 법제처 OC 인증 키
  LAW_GO_KR_BASE_URL    : 기본 http://www.law.go.kr/DRF
  LAW_GO_KR_TARGETS     : 사용할 대상 (law,prec,expc)
  LAW_RAW_DIR           : raw JSON 백업 디렉터리
  LAW_CHROMA_DIR        : ChromaDB persist 디렉터리
  LAW_EMBEDDING_MODEL   : HuggingFace 임베딩 모델 ID (기본 jhgan/ko-sroberta-multitask)
"""

from .chroma_index import ChromaIndex, SearchHit, get_default_index
from .chunking import (
    Chunk,
    chunk_interpretation,
    chunk_law,
    chunk_precedent,
    chunk_repair_price,
    chunk_static_laws,
)
from .lawgokr_client import LawGoKrClient

__all__ = [
    "ChromaIndex",
    "SearchHit",
    "get_default_index",
    "Chunk",
    "chunk_law",
    "chunk_precedent",
    "chunk_interpretation",
    "chunk_repair_price",
    "chunk_static_laws",
    "LawGoKrClient",
]
