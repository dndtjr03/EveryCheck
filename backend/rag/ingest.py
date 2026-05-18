"""법제처 API → raw JSON → chunk → ChromaDB 적재 통합 파이프라인.

CLI 사용:
    python -m rag.ingest --target law  --query "주택임대차보호법" --count 5
    python -m rag.ingest --target prec --query "원상회복 통상 손모" --count 30
    python -m rag.ingest --target expc --query "임대차" --count 10
    python -m rag.ingest --preset rental    # 임대차 도메인 일괄 수집 (추천)

raw JSON은 LAW_RAW_DIR 아래에 백업되므로, 재처리 시 API 재호출 불필요.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Iterable

from dotenv import load_dotenv

from .chroma_index import get_default_index
from .chunking import chunk_any, chunk_repair_price
from .lawgokr_client import LawGoKrClient, TargetType

load_dotenv()
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s %(name)s | %(message)s",
)
logger = logging.getLogger("rag.ingest")


# ── 도메인 사전 정의: 임대차 분쟁 ──────────────────────────────────────────

RENTAL_PRESET: list[tuple[TargetType, str, int]] = [
    # (target, query, 수집 개수)
    ("law", "주택임대차보호법", 1),
    ("law", "민법", 1),  # 615/654 조 포함
    ("law", "상가건물 임대차보호법", 1),
    ("prec", "원상회복 의무 통상 손모", 10),
    ("prec", "임대차 원상복구 비용", 10),
    ("prec", "벽지 도배 임차인 부담", 5),
    ("prec", "임대차 보증금 공제", 5),
    ("expc", "임대차 원상회복", 5),
    ("expc", "주택임대차보호법 적용", 5),
]


def ingest_target(
    client: LawGoKrClient,
    target: TargetType,
    query: str,
    count: int,
    raw_dir: Path,
) -> int:
    """단일 target+query에 대해 수집·청크·적재. 반환: 적재된 chunk 수."""
    logger.info("→ %s/%s (목표 %d건)", target, query, count)
    index = get_default_index()
    target_dir = raw_dir / target
    target_dir.mkdir(parents=True, exist_ok=True)

    total_chunks = 0
    collected = 0
    for item_id in client.iter_ids(target, query, max_count=count):
        try:
            if target == "law":
                detail = client.get_law(item_id)
            elif target == "prec":
                detail = client.get_precedent(item_id)
            elif target == "expc":
                detail = client.get_interpretation(item_id)
            else:
                continue
        except Exception as exc:
            logger.warning("  %s ID=%s 본문 조회 실패: %s", target, item_id, exc)
            continue

        # raw 백업
        raw_path = target_dir / f"{item_id}.json"
        client.dump_raw(detail, raw_path)

        # 청크 → ChromaDB
        chunks = list(chunk_any(target, detail))
        if chunks:
            index.upsert(chunks)
            total_chunks += len(chunks)
        collected += 1
        logger.info(
            "  • %s id=%s → chunks=%d (누적 %d)",
            target, item_id, len(chunks), total_chunks,
        )

    logger.info("← %s/%s: 본문 %d건, chunks %d개 적재", target, query, collected, total_chunks)
    return total_chunks


def _resolve_raw_dir() -> Path:
    """LAW_RAW_DIR을 backend/ 기준 절대 경로로 변환 (chroma_index._resolve와 동일 규칙)."""
    raw = os.getenv("LAW_RAW_DIR", "./backend/data/lawgokr/raw")
    p = Path(raw)
    if p.is_absolute():
        return p
    backend_dir = Path(__file__).resolve().parent.parent
    parts = p.parts
    if parts and parts[0] in (".", ""):
        parts = parts[1:]
    if parts and parts[0] == "backend":
        parts = parts[1:]
    if parts:
        return backend_dir / Path(*parts)
    return backend_dir / "data/lawgokr/raw"


def run_preset(preset: Iterable[tuple[TargetType, str, int]]) -> int:
    client = LawGoKrClient()
    raw_dir = _resolve_raw_dir()
    raw_dir.mkdir(parents=True, exist_ok=True)
    grand_total = 0
    for target, query, count in preset:
        grand_total += ingest_target(client, target, query, count, raw_dir)
    return grand_total


def ingest_repair_prices(json_path: Path | None = None) -> int:
    """LH 표준단가표 OCR JSON → ChromaDB 적재.

    기본 위치: backend/data/repair_price/repair_unit_prices.json
    raw API 호출이 없으므로 별도 경로. 임베딩만 수행.
    """
    if json_path is None:
        backend_dir = Path(__file__).resolve().parent.parent
        json_path = backend_dir / "data" / "repair_price" / "repair_unit_prices.json"
    if not json_path.exists():
        logger.error("단가표 JSON을 찾을 수 없습니다: %s", json_path)
        return 0
    payload = json.loads(json_path.read_text(encoding="utf-8"))
    chunks = chunk_repair_price(payload)
    if not chunks:
        logger.error("청크 생성 실패: %s", json_path)
        return 0
    index = get_default_index()
    index.upsert(chunks)
    logger.info("repair_price 적재 완료: %d chunks", len(chunks))
    return len(chunks)


def reindex_from_raw() -> int:
    """이미 백업된 raw JSON에서 chunking만 다시 수행 → ChromaDB 적재.
    API 재호출 없으므로 매우 빠름. chunking 로직 수정 후 호출."""
    raw_dir = _resolve_raw_dir()
    if not raw_dir.exists():
        logger.error("raw 디렉터리가 없습니다: %s", raw_dir)
        return 0
    index = get_default_index()
    total = 0
    for target in ("law", "prec", "expc"):
        sub = raw_dir / target
        if not sub.is_dir():
            continue
        files = list(sub.glob("*.json"))
        logger.info("→ %s : %d files", target, len(files))
        for path in files:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    payload = json.load(f)
            except Exception as exc:
                logger.warning("  %s 읽기 실패: %s", path.name, exc)
                continue
            chunks = list(chunk_any(target, payload))
            if not chunks:
                continue
            index.upsert(chunks)
            total += len(chunks)
            logger.info("  • %s/%s → %d chunks (누적 %d)",
                        target, path.stem, len(chunks), total)
    logger.info("=== reindex 완료: %d chunks ===", total)
    return total


def main() -> int:
    p = argparse.ArgumentParser(description="법제처 RAG ingestion")
    p.add_argument("--target", choices=["law", "prec", "expc"])
    p.add_argument("--query")
    p.add_argument("--count", type=int, default=20)
    p.add_argument(
        "--preset",
        choices=["rental"],
        help="도메인 사전정의 일괄 수집 (rental: 임대차 분쟁 전체)",
    )
    p.add_argument(
        "--reindex-raw",
        action="store_true",
        help="API 재호출 없이 이미 받아둔 raw JSON으로 ChromaDB 재적재",
    )
    p.add_argument(
        "--ingest-repair-prices",
        action="store_true",
        help="LH 2023 퇴거세대 원상복구비 표준단가표 JSON을 ChromaDB에 적재 "
        "(backend/data/repair_price/repair_unit_prices.json)",
    )
    p.add_argument(
        "--repair-prices-path",
        help="단가표 JSON 경로 직접 지정 (--ingest-repair-prices와 함께 사용)",
    )
    args = p.parse_args()

    if args.ingest_repair_prices:
        path = Path(args.repair_prices_path) if args.repair_prices_path else None
        ingest_repair_prices(path)
        index = get_default_index()
        logger.info("ChromaDB stats: %s",
                    json.dumps(index.stats(), ensure_ascii=False))
        return 0

    if args.reindex_raw:
        reindex_from_raw()
        index = get_default_index()
        logger.info("ChromaDB stats: %s",
                    json.dumps(index.stats(), ensure_ascii=False))
        return 0

    if args.preset == "rental":
        total = run_preset(RENTAL_PRESET)
        logger.info("=== preset 'rental' 완료: 총 %d chunks ===", total)
        index = get_default_index()
        logger.info("ChromaDB stats: %s", json.dumps(index.stats(), ensure_ascii=False))
        return 0

    if not args.target or not args.query:
        p.print_help()
        return 1

    client = LawGoKrClient()
    raw_dir = _resolve_raw_dir()
    raw_dir.mkdir(parents=True, exist_ok=True)
    total = ingest_target(client, args.target, args.query, args.count, raw_dir)
    logger.info("=== 완료: %d chunks ===", total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
