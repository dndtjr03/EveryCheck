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


_PHOTO_INSTRUCTION = """[역할]
당신은 한국 주택임대차 분쟁 자문 AI다. 입주 사진 없이 퇴거 사진 1장만 보고
국토부 임대차 가이드라인·민법 제615/654조·통상 손모 법리에 따라 판단한다.
입주 사진이 없으므로 비교 기준이 약하다 — 보수적으로 판단할 것.

[입력]
- 임대차 퇴거 시 원상복구 비용 산정용 손상 사진 1장.

[판단 기준]
* 통상 손모(자연 마모) → 임대인 부담: 전반적 변색, 가구 자국, 자연 들뜸, 노후화.
* 인위 파손 → 임차인 부담: 못 자국, 깊은 스크래치, 흡연·반려동물 흔적, 곰팡이 방치.
* 판단 보류: 사진 흐림·식별 불가.

[수행 단계 — 내부 추론. 출력 금지]
1. 손상 부위와 종류를 식별.
2. 통상 손모인지 인위 파손인지 보수적으로 분류 (입주 baseline 없으므로 의심스러우면 통상 손모).
3. LH 2023 표준단가 또는 일반 시세로 수리비 추정.

[confidence anchor]
- 0.8+ : 손상이 매우 명확. 인위 파손 가능성 명백.
- 0.5~0.7 : 손상은 보이나 원인·정도 추정.
- 0.5 미만 : 사진 품질·식별 어려움.

[출력 — JSON 1개. 마크다운/코드펜스/설명 금지]
{
  "part": "<부위. 예: 거실 벽지, 욕실 타일, 바닥 장판>",
  "damage_type": "<종류. 예: 스크래치, 오염, 곰팡이, 들뜸, 못 자국>",
  "cost": <정수, 원>,
  "confidence": <0.0~1.0>,
  "reason": "<한국어 1~3문장. 손상 부위·정도 + 통상 손모/인위 파손 판단 + 임차인 부담 가능성. '~로 보입니다', '~ 가능성이 있습니다' 처럼 완곡하게.>"
}

[예시 1 — 인위 파손]
{"part":"거실 벽지","damage_type":"낙서","cost":120000,"confidence":0.85,"reason":"거실 벽지에 어린이가 그린 듯한 펜 자국이 다수 보입니다. 통상 손모로 보기 어려운 인위 파손으로, 임차인 부담 가능성이 높습니다."}

[예시 2 — 통상 손모]
{"part":"바닥 장판","damage_type":"마모","cost":0,"confidence":0.7,"reason":"바닥 장판에 가구 자국과 전반적 마모가 보이나, 5년 이상 거주 시 통상 손모 범위로 보입니다. 임대인 수선의무 가능성이 있습니다."}
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
# /proxy/analyze-with-baseline (퇴거 사진 1장 + 입주 사진 N장 비교)
# -----------------------------


_COMPARE_INSTRUCTION = """[역할]
당신은 한국 주택임대차 분쟁 자문 AI다. 임대차 퇴거 시 원상복구 비용 분담을 다음 근거로 판단한다:
- 국토교통부 임대차 가이드라인 (감가상각: 경과연수/내용연수)
- 민법 제615조(원상회복의무), 제654조(준용)
- 주택임대차보호법
- 대법원 통상 손모 법리

[입력 이미지 순서]
- 1번 ~ N번 = 입주(과거 baseline) 사진. 임대인이 임차인에게 인도한 상태.
- 마지막 1장 = 퇴거(현재) 사진. 이것이 분석 대상.

[판단 기준 - 매우 중요]
* 통상 손모 (자연 마모) → 임대인 부담:
  - 일상 사용으로 생기는 변색·미세 마모·전반적 노후화.
  - 예: 거주 5년+ 후 벽지 누렇게 변색, 장판 자연 마모, 가구 무게 자국,
       에어컨 설치 자국, 노후 보일러 누수, 도배 자연 들뜸.
* 인위 파손 → 임차인 부담:
  - 부주의·고의·통상 범위 초과 사용.
  - 예: 못 자국 다수(10개+), 깊은 스크래치, 흡연 변색·악취, 반려동물 발톱,
       이사 중 가구로 벽 긁힘, 곰팡이 방치(환기 의무 위반).
* 판단 보류:
  - 사진이 흐려 손상 식별 어려움, 또는 같은 부위 매칭이 어려움.

[수행 단계 — 내부 추론용. 출력에 포함하지 말 것]
1. 퇴거 사진의 부위(벽/바닥/천장/가구/가전/욕실/주방 등)를 식별.
2. 입주 사진 1~N 중 같은 부위가 가장 잘 보이는 사진을 1장 선택.
3. 매칭된 입주 사진의 같은 부위와 퇴거 사진을 픽셀 단위로 비교해 새 손상을 식별.
4. 손상의 성격이 [통상 손모 / 인위 파손 / 판단 보류] 중 무엇에 해당하는지 분류.
5. LH 2023 표준단가 또는 일반 시세 기준으로 수리비를 보수적으로 추정.

[is_new 결정 규칙]
- true: 매칭된 입주 사진엔 없고 퇴거 사진에만 보이는 손상 AND 인위 파손에 가까움.
- false: 매칭된 입주 사진에 이미 비슷한 손상이 있음 OR 명백한 통상 손모.
- null: 매칭 사진이 없거나 판단이 모호함. 보수적으로 null 선택을 권장.

[confidence anchor]
- 0.9~1.0: 입주/퇴거 차이가 매우 명확. 인위 파손 명백.
- 0.7~0.8: 차이는 있으나 일부 추정.
- 0.5~0.6: 같은 부위 매칭은 했으나 손상 성격 모호.
- 0.0~0.4: 사진 품질 낮음 또는 매칭 불가.

[출력 형식 — JSON 1개. 마크다운/코드펜스/설명 금지]
{
  "part": "<문자열. 예: 거실 벽지, 욕실 타일, 바닥 장판, 주방 싱크대>",
  "damage_type": "<문자열. 예: 스크래치, 변색, 오염, 곰팡이, 들뜸, 못 자국, 흠집>",
  "cost": <정수. 원 단위. 0~수백만>,
  "confidence": <0.0~1.0 사이 소수>,
  "is_new": true | false | null,
  "matched_move_in_index": <1~N 정수 | null>,
  "reason": "<한국어 2~3문장. 반드시 포함: (1) 매칭한 입주 사진 번호와 비교 근거 (2) 통상 손모/인위 파손 판단 (3) 임대인/임차인 부담 가능성. '~로 보입니다', '~ 가능성이 높습니다'처럼 완곡하게.>"
}

[예시 1 — 인위 파손 (is_new=true)]
{"part":"거실 벽지","damage_type":"못 자국","cost":80000,"confidence":0.85,"is_new":true,"matched_move_in_index":2,"reason":"입주 사진 2번의 같은 벽면은 깨끗했으나 퇴거 사진에선 못 자국 5개가 보입니다. 통상 사용 범위를 초과한 인위 파손으로, 임차인 부담 가능성이 높습니다."}

[예시 2 — 통상 손모 (is_new=false)]
{"part":"거실 벽지","damage_type":"변색","cost":0,"confidence":0.75,"is_new":false,"matched_move_in_index":1,"reason":"입주 사진 1번과 비교하면 전반적으로 누런 변색이 진행됐으나, 5년 거주 기간을 고려할 때 통상 손모 범위로 보입니다. 국토부 가이드라인상 임대인 수선의무 가능성이 높습니다."}

[예시 3 — 판단 보류 (is_new=null)]
{"part":"욕실 천장","damage_type":"미상","cost":0,"confidence":0.3,"is_new":null,"matched_move_in_index":null,"reason":"입주 사진에 같은 욕실 천장이 명확히 나오지 않아 비교가 어렵습니다. 추가 사진을 확인하거나 임대인과 직접 협의를 권장합니다."}
"""


class CompareItem(BaseModel):
    matched_move_in_index: Optional[int] = None
    is_new: Optional[bool] = None
    part: str
    damage_type: str
    cost: int
    confidence: float
    reason: str


@router.post(
    "/analyze-with-baseline",
    summary="퇴거 사진 1장 + 입주 사진 N장 동시 입력 → 새 손상만 판별",
    description=(
        "Gemini Vision에 입주(baseline) 사진들과 퇴거 사진을 함께 보내고, "
        "퇴거 사진과 시각적으로 가장 비슷한 입주 사진을 자동 매칭한 뒤, "
        "그 입주 사진에 없던 손상만 '새로 생긴 손상'으로 판단한다. "
        "PRD 핵심 차별점: 1대1 매칭 + 시각 비교를 한 번의 호출로 처리."
    ),
)
async def analyze_photo_with_baseline(
    move_out_image: UploadFile = File(
        ..., description="퇴거(현재) 사진 — 분석 대상 1장"
    ),
    move_in_images: List[UploadFile] = File(
        ..., description="입주(baseline) 사진들 — 1~10장 권장"
    ),
    current_user: User = Depends(get_current_active_user),
) -> dict[str, Any]:
    _ensure_configured()

    if not move_in_images:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="입주 사진이 최소 1장 필요합니다. 입주 사진이 없으면 /proxy/analyze-photo 사용.",
        )
    if len(move_in_images) > 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="입주 사진은 최대 10장까지 허용됩니다.",
        )

    # 모든 사진 디코딩 (실패 시 어느 사진인지 메시지)
    async def _read_pil(uf: UploadFile, label: str) -> PIL.Image.Image:
        raw = await uf.read()
        if not raw:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{label} 이미지가 비어 있습니다.",
            )
        try:
            return PIL.Image.open(io.BytesIO(raw))
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{label} 디코딩 실패: {exc}",
            )

    move_in_pils: List[PIL.Image.Image] = []
    for i, mi in enumerate(move_in_images, start=1):
        move_in_pils.append(await _read_pil(mi, f"입주 {i}번"))
    move_out_pil = await _read_pil(move_out_image, "퇴거")

    # parts: instruction + 입주 1번 ~ 입주 N번 + 퇴거 사진 (이 순서가 프롬프트와 일치해야 함)
    parts: list[Any] = [_COMPARE_INSTRUCTION]
    for i, pil in enumerate(move_in_pils, start=1):
        parts.append(f"[입주 사진 {i}번]")
        parts.append(pil)
    parts.append("[퇴거 사진 — 분석 대상]")
    parts.append(move_out_pil)

    try:
        model = genai.GenerativeModel(_get_model_name())
        response = model.generate_content(parts)
        text = (response.text or "").strip()
    except Exception as exc:
        logger.exception("Gemini 호출 실패 (compare): %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Gemini 호출 실패: {exc}",
        )

    parsed = _parse_model_json(text)

    # 응답 정규화: 누락 필드 안전 처리. matched_move_in_index 범위 검증.
    idx = parsed.get("matched_move_in_index")
    if isinstance(idx, int) and not (1 <= idx <= len(move_in_pils)):
        idx = None  # 모델이 잘못된 번호를 줬으면 null로
    parsed["matched_move_in_index"] = idx
    parsed.setdefault("is_new", None)
    parsed.setdefault("part", "미상")
    parsed.setdefault("damage_type", "미상")
    parsed.setdefault("cost", 0)
    parsed.setdefault("confidence", 0.0)
    parsed.setdefault("reason", "추가 설명 없음")
    parsed["move_in_count"] = len(move_in_pils)  # 클라이언트가 매칭 인덱스 표시할 때 참고

    return parsed


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


_DEFAULT_SYSTEM = """당신은 한국 주택임대차 분쟁 자문 AI "다봐드림"입니다.

[역할]
사용자는 임대차 퇴거 시 원상복구 비용 분담을 알고 싶어합니다.
임대인/임차인 어느 쪽이 부담해야 하는지, 얼마인지, 어떤 근거로 그런지를
구체적·실용적으로 안내합니다.

[판단 기준 — 우선순위 순]
1. 국토교통부 임대차 가이드라인 (감가상각: 임차인 부담 = 총 수리비 × (1 - 경과연수/내용연수))
2. 민법 제615조(원상회복의무), 제654조(준용)
3. 주택임대차보호법
4. 대법원 통상 손모 법리 (예: 대법원 2018다252410)

[통상 손모 vs 인위 파손 — 매우 중요]
* 통상 손모(자연 마모) = 임대인 부담:
  - 5년+ 거주 후 벽지 누렇게 변색, 장판 자연 마모, 가구 무게 자국,
    에어컨 설치 자국, 노후 보일러 누수, 도배 자연 들뜸, 베란다 페인트 변색.
* 인위 파손 = 임차인 부담:
  - 못 자국 다수, 깊은 스크래치, 흡연 변색·악취, 반려동물 발톱,
    이사 중 가구로 벽 긁힘, 곰팡이 방치(환기 의무 위반).

[답변 원칙]
- 단정적 법률 자문 금지. "가능성이 높습니다", "분쟁 시 다툴 여지가 있습니다" 처럼 완곡하게.
- 한국어. 짧고 명확. 필요 시 근거(가이드라인 조문·판례 번호·LH 표준단가)를 구체 인용.
- RAG로 제공된 [관련 근거]가 있으면 답변에 반드시 인용. 인용 형식:
  - 법령: "주택임대차보호법 제6조의2"
  - 판례: "대법원 2018다252410"
  - 단가: "벽지 도배 14,100원/㎡ (LH 2023 표준단가)"
- 분석 결과(`is_new`, `matched_move_in_index`, `cost` 등)가 있으면 그 결과를 근거로 후속 답변.
- 수리비를 추정할 때는 단가 × 면적/수량을 명시하고, 감가상각이 적용 가능하면 함께 계산.

[응답 톤]
- 친절하고 침착하게. 사용자가 흥분 상태일 수 있으므로 객관적 사실로 가라앉히기.
- 임대인·임차인 어느 쪽 편도 들지 말고 사실관계 + 법적 판단 가능성을 균형 있게.
"""


# 채팅 1회당 검색할 소스별 결과 수.
# - 단일 query()만 호출하면 단가(repair_price)가 71청크로 가장 많아 상위 결과를
#   독차지하고 판례·법령이 밀려나는 현상이 있어, 소스 종류별로 따로 조회해 섞는다.
# - 합계 5건. Gemini system prompt 토큰 절약 + 다양한 출처 인용 균형.
_RAG_MIX: list[tuple[str, int]] = [
    ("repair_price", 1),   # LH 표준단가표
    ("precedent", 2),      # 판례
    ("law", 1),            # 법령(민법·주임법·국토부 가이드라인 — 정적 적재)
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
            "─────────────────────────────────────\n"
            "[관련 근거 — 답변 작성 시 적극 활용할 것]\n"
            "아래 근거는 사용자 질문에 대해 의미 기반 검색(임베딩)으로 가져온\n"
            "관련성 높은 문서 발췌입니다. 출처는 두 가지:\n"
            "  (1) 법제처 OpenAPI: 판례·법령·해석례 (각 근거에 source_url 포함)\n"
            "  (2) LH 한국토지주택공사 2023년 퇴거세대 원상복구비 표준단가표\n"
            "\n"
            "활용 지침:\n"
            "- 답변 본문에 최소 1건은 구체적으로 인용 (단순 일반론 답변 금지).\n"
            "- 인용 형식 예시:\n"
            "    · 법령: \"주택임대차보호법 제6조의2에 따르면…\"\n"
            "    · 판례: \"대법원 2018다252410 판결은 통상 손모를…\"\n"
            "    · 단가: \"벽지 도배는 LH 2023 표준단가 14,100원/㎡ 기준으로…\"\n"
            "- 표준단가가 있는 항목은 단가 × 면적(or 수량) → 감가상각률 적용까지\n"
            "  3단계 계산을 같이 보여줘서 사용자가 검증 가능하도록.\n"
            "- 근거에 명시되지 않은 숫자나 판례를 임의로 만들어 인용하지 말 것.\n"
            "- 유사도가 낮아 근거가 질문과 관련 없어 보이면, 무리해서 인용하지 말고\n"
            "  '관련 판례를 찾기 어려워 일반 가이드라인으로 답변드립니다'라고 명시.\n"
            "─────────────────────────────────────\n"
            f"\n{rag_context}\n"
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
