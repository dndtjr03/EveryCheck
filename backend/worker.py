"""Celery 워커 태스크: Google Gemini로 손상 이미지 분석.

구 RepairEstimate/DamageImage 모델을 폐기하고 AnalysisPhoto 단일 행 기반으로 동작한다.
태스크 인자는 analysis_photo_id(int) — analysis_photos 테이블의 PK.
"""

import io
import json
import logging
import os
import re
from typing import Any, Optional

import google.generativeai as genai
import PIL.Image

from celery_app import celery_app
from database import session_scope
from models import AnalysisPhoto, apply_ai_analysis_result, mark_analysis_failed
from utils import compute_moliti_depreciation_tenant_cost, download_bytes_from_s3_url

logger = logging.getLogger(__name__)

_JSON_INSTRUCTION = """이 이미지는 임대차 퇴거 시 원상복구 비용 산정을 위한 손상 사진이다.
다음 항목만 추정하여 반드시 JSON 한 개만 출력하라. 다른 설명·마크다운·코드펜스는 절대 쓰지 마라.
키는 반드시 영문 소문자로 다음과 같다:
- "part": 손상이 있는 부위 (예: 거실 벽면, 욕실 타일, 바닥 장판) — 문자열
- "damage_type": 손상 종류 (예: 스크래치, 오염, 곰팡이, 들뜸) — 문자열
- "cost": 국내 시공 기준 추정 수리비(원화, 정수) — 숫자
- "confidence": 위 추정에 대한 확신도 — 0 이상 1 이하 소수

출력 예시 형식(이 한 줄짜리 JSON만):
{"part":"...","damage_type":"...","cost":120000,"confidence":0.75}
"""


def _parse_model_json(text: str) -> dict[str, Any]:
    """모델 응답에서 JSON 객체를 추출해 파싱한다."""
    raw = text.strip()
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw)
    if fence:
        raw = fence.group(1).strip()
    return json.loads(raw)


def _clamp01(value: Optional[Any]) -> Optional[float]:
    if value is None:
        return None
    try:
        x = float(value)
    except (TypeError, ValueError):
        return None
    return max(0.0, min(1.0, x))


@celery_app.task(
    name="worker.analyze_image_task",
    autoretry_for=(Exception,),
    max_retries=3,
    retry_backoff=True,
    retry_backoff_max=120,
)
def analyze_image_task(analysis_photo_id: int) -> dict[str, Any]:
    """S3에 올라간 손상 이미지를 Gemini로 분석하고 analysis_photos 행을 갱신한다.

    TODO(Wave 2): 현재 /analyze 엔드포인트는 제거된 상태. 이 태스크는
    `routers/analysis.py`의 신규 분석 큐잉 엔드포인트에서 호출되도록 통합 필요.
    """
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        logger.error("GOOGLE_API_KEY is not set")
        with session_scope() as db:
            mark_analysis_failed(db, analysis_photo_id)
        return {"ok": False, "error": "missing_google_api_key"}

    genai.configure(api_key=api_key)
    model_name = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")

    s3_url: Optional[str] = None
    file_hash: Optional[str] = None
    elapsed_years: float = 0.0
    useful_life_years: float = 10.0

    with session_scope() as db:
        photo = (
            db.query(AnalysisPhoto)
            .filter(AnalysisPhoto.id == analysis_photo_id)
            .first()
        )
        if photo is None:
            return {"ok": False, "error": "analysis_photo_not_found"}
        if not photo.s3_url:
            mark_analysis_failed(db, analysis_photo_id)
            return {"ok": False, "error": "no_s3_url"}
        s3_url = photo.s3_url
        file_hash = photo.file_hash
        if photo.elapsed_years is not None:
            elapsed_years = photo.elapsed_years
        if photo.useful_life_years is not None:
            useful_life_years = photo.useful_life_years

    try:
        image_bytes, _mime = download_bytes_from_s3_url(s3_url)
    except Exception as exc:
        logger.exception("S3 download failed: %s", exc)
        with session_scope() as db:
            mark_analysis_failed(db, analysis_photo_id)
        return {"ok": False, "error": "s3_download_failed"}

    try:
        pil_image = PIL.Image.open(io.BytesIO(image_bytes))
        model = genai.GenerativeModel(model_name)
        response = model.generate_content([_JSON_INSTRUCTION, pil_image])
        raw_text = (response.text or "").strip()
        if not raw_text:
            raise ValueError("empty model response")
        data = _parse_model_json(raw_text)
    except Exception as exc:
        logger.exception("Gemini analysis failed: %s", exc)
        with session_scope() as db:
            mark_analysis_failed(db, analysis_photo_id)
        return {"ok": False, "error": "analysis_failed"}

    part = data.get("part")
    damage_type = data.get("damage_type")
    if part is not None:
        part = str(part)[:255]
    if damage_type is not None:
        damage_type = str(damage_type)[:64]

    try:
        cost = float(data.get("cost", 0))
    except (TypeError, ValueError):
        cost = 0.0
    cost = max(cost, 0.0)

    confidence = _clamp01(data.get("confidence"))

    with session_scope() as db:
        photo = (
            db.query(AnalysisPhoto)
            .filter(AnalysisPhoto.id == analysis_photo_id)
            .first()
        )
        if photo is None:
            return {"ok": False, "error": "analysis_photo_not_found"}

        estimated_final = compute_moliti_depreciation_tenant_cost(
            cost,
            elapsed_years,
            useful_life_years,
        )

        updated = apply_ai_analysis_result(
            db,
            analysis_photo_id,
            part=part,
            damage_type=damage_type,
            cost_total=cost,
            estimated_cost=estimated_final,
            confidence=confidence,
            image_hash=file_hash,
        )
        if updated is None:
            return {"ok": False, "error": "analysis_photo_not_found"}

    return {
        "ok": True,
        "analysis_photo_id": analysis_photo_id,
        "part": part,
        "damage_type": damage_type,
        "cost_total": cost,
        "estimated_cost": estimated_final,
        "confidence": confidence,
    }
