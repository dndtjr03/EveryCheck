"""Flutter 앱이 Gemini 키를 들고 다니지 않도록 백엔드가 대신 호출해주는 라우터.

- POST /proxy/analyze-photo : 손상 사진 1장 → JSON 분석 결과
- POST /proxy/chat          : 분석 결과+후속 질문 → AI 답변 (양방향 채팅)

기존 워커(`worker.py`)는 Celery 비동기 분석용. 본 라우터는 채팅 UX를 위해
동기적으로 즉시 응답해야 하므로 별도 구현. Gemini 클라이언트 호출 패턴은
worker.py와 동일하다.
"""

from __future__ import annotations

import io
import json
import logging
import os
import re
from typing import Any, List, Literal, Optional

import google.generativeai as genai
import PIL.Image
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, Field

from auth import get_current_active_user
from models import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/proxy", tags=["analysis-proxy"])


# -----------------------------
# 공통 설정
# -----------------------------


def _get_model_name() -> str:
    return os.getenv("GEMINI_MODEL", "gemini-1.5-flash")


def _ensure_configured() -> None:
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GOOGLE_API_KEY가 서버에 설정되지 않았습니다.",
        )
    genai.configure(api_key=api_key)


def _parse_model_json(text: str) -> dict[str, Any]:
    raw = (text or "").strip()
    if not raw:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Gemini 응답이 비어 있습니다.",
        )
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw)
    if fence:
        raw = fence.group(1).strip()
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini 응답 파싱 실패: {exc}",
        )
    if not isinstance(decoded, dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Gemini 응답이 JSON object 형태가 아닙니다.",
        )
    return decoded


# -----------------------------
# /proxy/analyze-photo
# -----------------------------


_PHOTO_INSTRUCTION = """이 이미지는 임대차 퇴거 시 원상복구 비용 산정을 위한 손상 사진이다.
다음 항목만 추정하여 반드시 JSON 한 개만 출력하라. 다른 설명·마크다운·코드펜스는 절대 쓰지 마라.

키 (영문 소문자):
- "part": 손상 부위 (예: 거실 벽면, 욕실 타일, 바닥 장판) — 문자열
- "damage_type": 손상 종류 (예: 스크래치, 오염, 곰팡이, 들뜸) — 문자열
- "cost": 국내 시공 기준 추정 수리비(원화, 정수) — 숫자
- "confidence": 추정 확신도 — 0~1 사이 소수
- "reason": 사용자에게 보여줄 한국어 설명 (1~3문장, 손상 부위·정도·임차인 부담 가능성 포함)

출력 예:
{"part":"거실 벽지","damage_type":"오염","cost":120000,"confidence":0.75,"reason":"거실 벽지 하단부에 오염이 보입니다. 통상 손모로 보기 어려운 정도로, 임차인 부담 가능성이 있습니다."}
"""


@router.post(
    "/analyze-photo",
    summary="손상 사진 1장 분석 (동기, 채팅 UI용)",
    description="multipart 이미지 업로드 → Gemini로 즉시 분석한 JSON 결과 반환.",
)
async def analyze_photo(
    image: UploadFile = File(..., description="손상 사진 파일"),
    current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    _ensure_configured()

    raw_bytes = await image.read()
    if not raw_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="이미지 파일이 비어 있습니다.",
        )

    try:
        pil_image = PIL.Image.open(io.BytesIO(raw_bytes))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"이미지 디코딩 실패: {exc}",
        )

    try:
        model = genai.GenerativeModel(_get_model_name())
        response = model.generate_content([_PHOTO_INSTRUCTION, pil_image])
        text = (response.text or "").strip()
    except Exception as exc:
        logger.exception("Gemini 호출 실패: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini 호출 실패: {exc}",
        )

    return _parse_model_json(text)


# -----------------------------
# /proxy/chat
# -----------------------------


class ChatTurn(BaseModel):
    role: Literal["user", "model"] = Field(
        ..., description="Gemini 채팅 history에서의 역할. 'user' 또는 'model'."
    )
    text: str = Field(..., description="해당 턴의 텍스트 내용")


class ChatRequest(BaseModel):
    history: List[ChatTurn] = Field(
        default_factory=list, description="이전 대화 기록 (가장 오래된 → 최신 순서)"
    )
    message: str = Field(..., description="현재 사용자가 보낸 새 메시지")
    system_context: Optional[str] = Field(
        default=None,
        description="시스템 프롬프트 (분석 요약·도메인 안내 등)",
    )


class ChatResponse(BaseModel):
    reply: str


_DEFAULT_SYSTEM = """당신은 한국 임대차 분쟁 자문 보조 AI "다봐드림"입니다.
- 사용자는 임대차 퇴거 시 원상복구 비용 분담을 알고 싶어합니다.
- 국토교통부 임대차 가이드라인과 민법 제615조(원상회복의무), 제654조(준용),
  주택임대차보호법, 그리고 통상의 손모 법리(대법원 판례 다수)를 근거로 답하세요.
- 단정적인 법률 자문은 피하고, "가능성이 높다" / "분쟁 시 다툴 여지가 있다" 같이 완곡하게 표현하세요.
- 응답은 항상 한국어. 짧고 명확하게 답하되, 필요 시 근거(가이드라인·민법 조문·판례 요지)를 인용하세요.
- 분석 결과 요약을 받았다면 그 결과를 바탕으로 후속 질문에 답합니다.
"""


# 채팅 1회당 검색할 소스별 결과 수.
# - 단일 query()만 호출하면 단가(repair_price)가 71청크로 가장 많아 상위 결과를
#   독차지하고 판례·법령이 밀려나는 현상이 있어, 소스 종류별로 따로 조회해 섞는다.
# - 합계 4건. (기존 6건에서 줄여 Gemini system prompt 토큰 절약 → 응답 시작 ↑)
# - law는 현재 ChromaDB 적재 0건이라 mix에서 제외 (향후 적재 시 복원).
_RAG_MIX: list[tuple[str, int]] = [
    ("repair_price", 1),   # LH 표준단가표
    ("precedent", 2),      # 판례
    ("interpretation", 1), # 법령해석례
]

# 청크 본문을 시스템 프롬프트에 넣을 때 자르는 길이. 600 → 350으로 줄여 토큰 절약.
_CHUNK_PREVIEW_CHARS = 350


def _retrieve_rag_context(query: str) -> str:
    """source_type별로 분리 검색해 다양성을 확보한 RAG 컨텍스트 문자열.

    인덱스가 비어 있거나 로드 실패해도 채팅은 계속되도록 빈 문자열 반환.
    """
    try:
        from rag import get_default_index  # 지연 로드 (초기 임포트 비용 회피)
        index = get_default_index()
        if index.count() == 0:
            return ""
        hits = []
        for st, k in _RAG_MIX:
            try:
                hits.extend(index.query(query, n_results=k, source_type=st))
            except Exception as exc:
                logger.warning("RAG source_type=%s 검색 실패: %s", st, exc)
        # 유사도 내림차순 정렬 (다양성 + 정확도 균형)
        hits.sort(key=lambda h: h.score, reverse=True)
    except Exception as exc:
        logger.warning("RAG 검색 실패 (채팅은 계속 진행): %s", exc)
        return ""

    if not hits:
        return ""

    blocks: list[str] = []
    for i, h in enumerate(hits, start=1):
        meta = h.metadata or {}
        src = meta.get("source_type", "")
        if src == "law":
            label = f"[법령] {meta.get('law_name','')} {meta.get('article_no','')}"
        elif src == "precedent":
            label = f"[판례] {meta.get('court','')} {meta.get('case_no','')}"
        elif src == "interpretation":
            label = f"[해석례] {meta.get('title','')}"
        elif src == "repair_price":
            price = meta.get("unit_price")
            unit = meta.get("unit", "")
            price_part = f" = {int(price):,}원{unit}" if isinstance(price, (int, float)) else ""
            label = (
                f"[표준단가] {meta.get('category','')} / "
                f"{meta.get('item','')}{price_part}"
            )
        else:
            label = "[참고]"
        url = meta.get("source_url", "")
        url_part = f" ({url})" if url else ""
        blocks.append(
            f"근거 {i} (유사도 {h.score:.2f}) {label}{url_part}\n"
            f"{h.text[:_CHUNK_PREVIEW_CHARS]}"
        )

    return "\n\n".join(blocks)


@router.post(
    "/chat",
    response_model=ChatResponse,
    summary="분석 결과 + 후속 질문 + 판례 RAG 컨텍스트를 묶어 Gemini 양방향 채팅",
)
async def chat(
    body: ChatRequest,
    current_user: User = Depends(get_current_active_user),
) -> ChatResponse:
    _ensure_configured()

    if not body.message.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="메시지가 비어 있습니다.",
        )

    # RAG: source_type별로 분리 검색 (단가 2 + 판례 2 + 법령 1 + 해석례 1).
    # 자세한 분배는 _RAG_MIX 참고.
    rag_context = _retrieve_rag_context(body.message)

    base_system = body.system_context or _DEFAULT_SYSTEM
    if rag_context:
        system_instruction = (
            f"{base_system}\n\n"
            "다음은 두 가지 출처에서 임베딩한 관련 근거입니다.\n"
            " (1) 법제처 OpenAPI에서 수집한 법령·판례·해석례\n"
            " (2) LH 한국토지주택공사 2023년 퇴거세대 원상복구비 표준단가표\n"
            "답변할 때 가능한 한 이 근거를 인용하세요.\n"
            "- 법률 인용 예: '주택임대차보호법 제6조의2', '대법원 2018다252410'\n"
            "- 단가 인용 예: '벽지 도배 14,100원/㎡ (LH 2023 표준단가)'\n"
            "수리비 금액을 추정할 때는 표준단가가 있으면 단가 × 면적(또는 수량) - "
            "감가상각률 적용으로 계산 근거를 함께 제시하세요. "
            "감가상각률 = 경과연수 / 수선주기.\n\n"
            f"[관련 근거]\n{rag_context}"
        )
    else:
        system_instruction = base_system

    try:
        model = genai.GenerativeModel(
            model_name=_get_model_name(),
            system_instruction=system_instruction,
        )
        history_contents = [
            {"role": t.role, "parts": [t.text]} for t in body.history
        ]
        chat_session = model.start_chat(history=history_contents)
        response = chat_session.send_message(body.message)
        reply = (response.text or "응답을 받지 못했어요.").strip()
    except Exception as exc:
        logger.exception("Gemini 채팅 실패: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini 채팅 호출 실패: {exc}",
        )

    return ChatResponse(reply=reply)
