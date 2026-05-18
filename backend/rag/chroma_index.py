"""ChromaDB + 한국어 임베딩 모델 추상화.

- 컬렉션 1개에 source_type 메타데이터로 필터링하는 단일 컬렉션 전략 사용.
- 임베딩은 기본 `jhgan/ko-sroberta-multitask` (CPU 실행, 768차원).
- 처음 로드 시 모델 다운로드 약 400MB.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

import chromadb
from chromadb.config import Settings
from chromadb.utils.embedding_functions import SentenceTransformerEmbeddingFunction
from dotenv import load_dotenv

from .chunking import Chunk

logger = logging.getLogger(__name__)
load_dotenv()


def _resolve_under_backend(path: str, fallback_rel: str) -> str:
    """상대 경로를 backend/ 폴더 기준 절대 경로로 변환.

    backend/rag/chroma_index.py 파일 위치 기준으로 backend 디렉터리를 찾고,
    그 아래에 fallback_rel을 붙인다. 입력이 절대 경로면 그대로 사용.
    """
    p = Path(path)
    if p.is_absolute():
        return str(p)
    backend_dir = Path(__file__).resolve().parent.parent  # backend/rag/.. = backend
    # 입력이 "./backend/..." 같이 시작하면 한 단계 끊어내고 backend 아래로
    parts = p.parts
    if parts and parts[0] in (".", ""):
        parts = parts[1:]
    if parts and parts[0] == "backend":
        parts = parts[1:]
    if parts:
        return str(backend_dir / Path(*parts))
    return str(backend_dir / fallback_rel)


@dataclass
class SearchHit:
    chunk_id: str
    text: str
    score: float
    metadata: dict[str, Any]


_DEFAULT_COLLECTION = "lawgokr"


class ChromaIndex:
    """프로젝트 RAG용 ChromaDB 래퍼."""

    def __init__(
        self,
        persist_dir: Optional[str] = None,
        *,
        collection_name: str = _DEFAULT_COLLECTION,
        embedding_model: Optional[str] = None,
    ):
        # .env의 상대 경로(./backend/...)는 실행 디렉터리에 따라 다르게 풀리므로,
        # backend/ 폴더를 기준으로 절대 경로로 normalize.
        raw = persist_dir or os.getenv(
            "LAW_CHROMA_DIR", "./backend/data/lawgokr/chroma"
        )
        self.persist_dir = _resolve_under_backend(raw, "data/lawgokr/chroma")
        Path(self.persist_dir).mkdir(parents=True, exist_ok=True)

        self.collection_name = collection_name
        self.embedding_model = embedding_model or os.getenv(
            "LAW_EMBEDDING_MODEL", "jhgan/ko-sroberta-multitask"
        )

        self._client = chromadb.PersistentClient(
            path=self.persist_dir,
            settings=Settings(anonymized_telemetry=False),
        )
        self._embed_fn = SentenceTransformerEmbeddingFunction(
            model_name=self.embedding_model,
        )
        # NOTE: ChromaDB 0.5.5 ~ 0.5.17 에는 metadata={"hnsw:space": ...} 호환성
        # 버그(KeyError: '_type')가 있어 metadata 인자를 생략한다. 기본 거리(L2) 사용.
        # 0.5.18+ 로 업그레이드 시 metadata={"hnsw:space": "cosine"} 다시 추가 권장.
        self._collection = self._client.get_or_create_collection(
            name=self.collection_name,
            embedding_function=self._embed_fn,
        )

    # ── 적재 ────────────────────────────────────────────────────────────

    def upsert(self, chunks: list[Chunk]) -> int:
        """기존 chunk_id면 덮어쓰고 없으면 추가."""
        if not chunks:
            return 0
        ids = [c.chunk_id for c in chunks]
        docs = [c.text for c in chunks]
        metas = [c.metadata for c in chunks]
        self._collection.upsert(ids=ids, documents=docs, metadatas=metas)
        logger.info("ChromaDB upsert: %d chunks", len(chunks))
        return len(chunks)

    # ── 검색 ────────────────────────────────────────────────────────────

    def query(
        self,
        query_text: str,
        *,
        n_results: int = 5,
        source_type: Optional[str] = None,
    ) -> list[SearchHit]:
        """벡터 유사도 검색. source_type으로 필터링 가능."""
        where = {"source_type": source_type} if source_type else None
        result = self._collection.query(
            query_texts=[query_text],
            n_results=n_results,
            where=where,
        )
        ids = result.get("ids", [[]])[0]
        docs = result.get("documents", [[]])[0]
        metas = result.get("metadatas", [[]])[0]
        dists = result.get("distances", [[]])[0]

        hits: list[SearchHit] = []
        for i, cid in enumerate(ids):
            # 기본 L2 거리 → 유사도(0~1)로 환산. 작을수록 유사. 1/(1+d)로 단순 변환.
            d = float(dists[i]) if i < len(dists) else 1.0
            sim = 1.0 / (1.0 + d)
            hits.append(
                SearchHit(
                    chunk_id=cid,
                    text=docs[i] if i < len(docs) else "",
                    score=sim,
                    metadata=metas[i] if i < len(metas) else {},
                )
            )
        return hits

    # ── 통계 ────────────────────────────────────────────────────────────

    def count(self) -> int:
        return self._collection.count()

    def stats(self) -> dict[str, Any]:
        return {
            "collection": self.collection_name,
            "persist_dir": self.persist_dir,
            "embedding_model": self.embedding_model,
            "count": self.count(),
        }


# ── 싱글톤 ─────────────────────────────────────────────────────────────────

_default_index: Optional[ChromaIndex] = None


def get_default_index() -> ChromaIndex:
    """프로세스 단위 싱글톤. 임베딩 모델 로드는 최초 1회만."""
    global _default_index
    if _default_index is None:
        _default_index = ChromaIndex()
    return _default_index
