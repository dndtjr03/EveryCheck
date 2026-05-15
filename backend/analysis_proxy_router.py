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


@router.post(
    "/chat",
    response_model=ChatResponse,
    summary="분석 결과 + 후속 질문을 가지고 Gemini와 양방향 채팅",
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

    system_instruction = body.system_context or _DEFAULT_SYSTEM

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
