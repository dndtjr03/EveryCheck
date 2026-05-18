"""판례·법령 검색 라우터 (RAG).

ChromaDB에 적재된 법제처 데이터를 의미 유사도로 검색해 반환한다.
앱·내부 모듈(analysis_proxy_router) 어디서든 호출 가능.
"""

from __future__ import annotations

import logging
from typing import Any, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from auth import get_current_active_user
from models import User
from rag import SearchHit, get_default_index

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/precedents", tags=["precedents"])


SourceTypeLiteral = Literal["law", "precedent", "interpretation"]


class PrecedentSearchRequest(BaseModel):
    query: str = Field(..., description="검색어 (자연어)", min_length=1)
    n_results: int = Field(5, ge=1, le=20, description="반환할 결과 수")
    source_type: Optional[SourceTypeLiteral] = Field(
        None,
        description="필터: law(법령) / precedent(판례) / interpretation(해석례). 비우면 전부.",
    )


class PrecedentHit(BaseModel):
    chunk_id: str
    text: str
    score: float
    metadata: dict[str, Any]


class PrecedentSearchResponse(BaseModel):
    query: str
    count: int
    hits: list[PrecedentHit]


def _to_hit(h: SearchHit) -> PrecedentHit:
    return PrecedentHit(
        chunk_id=h.chunk_id, text=h.text, score=h.score, metadata=h.metadata
    )


@router.post(
    "/search",
    response_model=PrecedentSearchResponse,
    summary="판례·법령·해석례 의미 검색 (RAG)",
    description=(
        "법제처 OpenAPI로 미리 적재한 ChromaDB에서 query와 의미적으로 가까운 "
        "조문/판례/해석례 Top-N을 반환합니다. analysis 채팅 컨텍스트, PDF 인용 "
        "근거, 앱의 판례 탐색 화면 등에서 공통 사용합니다."
    ),
)
def search_precedents(
    body: PrecedentSearchRequest,
    current_user: User = Depends(get_current_active_user),
) -> PrecedentSearchResponse:
    try:
        index = get_default_index()
    except Exception as exc:
        logger.exception("ChromaDB 로드 실패: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"RAG 인덱스 초기화 실패: {exc}",
        )

    hits = index.query(
        query_text=body.query,
        n_results=body.n_results,
        source_type=body.source_type,
    )
    return PrecedentSearchResponse(
        query=body.query,
        count=len(hits),
        hits=[_to_hit(h) for h in hits],
    )


@router.get(
    "/stats",
    summary="RAG 인덱스 상태",
    description="ChromaDB 컬렉션 메타데이터와 적재된 chunk 수를 반환.",
)
def stats(
    current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    try:
        index = get_default_index()
        return index.stats()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"RAG 인덱스 로드 실패: {exc}",
        )
