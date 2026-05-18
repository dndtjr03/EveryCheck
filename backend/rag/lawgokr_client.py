"""법제처 OpenAPI 클라이언트 (검색·본문).

법제처 OpenAPI: https://open.law.go.kr
  - 검색  : {BASE}/lawSearch.do?OC={KEY}&target={target}&type=JSON&query=...
  - 본문  : {BASE}/lawService.do?OC={KEY}&target={target}&type=JSON&ID={일련번호}

target 값:
  - law   : 현행 법령
  - prec  : 판례 (대법원·하급심)
  - expc  : 법령해석례
  - admrul: 행정규칙

JSON 응답은 target에 따라 키 구조가 다르므로 호출하는 쪽에서 적절히 parse.
"""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any, Iterable, Literal, Optional

import requests
from dotenv import load_dotenv

logger = logging.getLogger(__name__)
load_dotenv()

TargetType = Literal["law", "prec", "expc", "admrul"]


class LawGoKrClient:
    """법제처 OpenAPI 동기 클라이언트.

    rate limit: 법제처 가이드상 명시적 한도 없음. 안전을 위해 호출 사이 0.2초 sleep.
    실패 시 최대 3회 재시도 (지수 백오프).
    """

    def __init__(
        self,
        oc: Optional[str] = None,
        base_url: Optional[str] = None,
        *,
        timeout: int = 15,
        sleep_between_calls: float = 0.2,
    ):
        self.oc = oc or os.getenv("LAW_GO_KR_OC", "")
        if not self.oc:
            raise RuntimeError(
                "LAW_GO_KR_OC 환경변수가 비어 있습니다. .env에 OC 키를 등록하세요."
            )
        self.base_url = (
            base_url or os.getenv("LAW_GO_KR_BASE_URL", "http://www.law.go.kr/DRF")
        ).rstrip("/")
        self.timeout = timeout
        self.sleep_between_calls = sleep_between_calls

    # ── 내부 ────────────────────────────────────────────────────────────

    def _call(self, path: str, params: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}/{path}"
        merged = {"OC": self.oc, "type": "JSON", **params}
        last_exc: Optional[Exception] = None
        for attempt in range(3):
            try:
                resp = requests.get(url, params=merged, timeout=self.timeout)
                resp.raise_for_status()
                # 법제처는 가끔 HTML 에러 페이지를 200으로 반환 — JSON 디코딩 실패 시 재시도
                try:
                    return resp.json()
                except json.JSONDecodeError as exc:
                    last_exc = exc
                    # XML 인 경우엔 type=XML로 회신될 수도 있어 한 번 더
                    logger.warning(
                        "법제처 JSON 파싱 실패 (시도 %s) — 본문 앞 200자: %s",
                        attempt + 1,
                        resp.text[:200],
                    )
            except requests.RequestException as exc:
                last_exc = exc
                logger.warning("법제처 호출 실패 (시도 %s): %s", attempt + 1, exc)
            time.sleep(0.5 * (2 ** attempt))
        raise RuntimeError(f"법제처 API 호출 실패: {last_exc}")

    # ── 검색 ────────────────────────────────────────────────────────────

    def search(
        self,
        target: TargetType,
        query: str,
        *,
        display: int = 20,
        page: int = 1,
        search_in_body: bool = True,
    ) -> dict[str, Any]:
        """목록 검색.

        법제처 lawSearch.do는 기본적으로 사건명(evtNm)에서만 매칭함.
        → 판례·해석례는 본문 검색(search=2)으로 매칭 범위를 넓혀야 결과가 잡힘.
        법령(law)에는 search=2가 의미 없으므로 적용 안 함.
        """
        params: dict[str, Any] = {
            "target": target,
            "query": query,
            "display": min(display, 100),
            "page": page,
        }
        if search_in_body and target in ("prec", "expc"):
            params["search"] = "2"  # 본문 검색
        result = self._call("lawSearch.do", params)
        time.sleep(self.sleep_between_calls)
        return result

    # ── 본문 ────────────────────────────────────────────────────────────

    def get_law(self, law_id: str) -> dict[str, Any]:
        """법령 본문 조회."""
        result = self._call("lawService.do", {"target": "law", "ID": law_id})
        time.sleep(self.sleep_between_calls)
        return result

    def get_precedent(self, prec_id: str) -> dict[str, Any]:
        """판례 본문 조회."""
        result = self._call("lawService.do", {"target": "prec", "ID": prec_id})
        time.sleep(self.sleep_between_calls)
        return result

    def get_interpretation(self, expc_id: str) -> dict[str, Any]:
        """법령해석례 본문 조회."""
        result = self._call("lawService.do", {"target": "expc", "ID": expc_id})
        time.sleep(self.sleep_between_calls)
        return result

    # ── 편의 메서드: 검색 결과에서 ID 추출 ──────────────────────────────

    @staticmethod
    def extract_ids(search_result: dict[str, Any], target: TargetType) -> list[str]:
        """검색 응답에서 일련번호 목록 추출. target별 키 구조가 다름."""
        if target == "law":
            root = search_result.get("LawSearch", {})
            items = root.get("law", [])
        elif target == "prec":
            root = search_result.get("PrecSearch", {})
            items = root.get("prec", [])
        elif target == "expc":
            root = search_result.get("Expc", {})
            items = root.get("expc", [])
        else:
            items = []

        if isinstance(items, dict):
            items = [items]

        ids: list[str] = []
        for it in items:
            for key in ("법령일련번호", "판례일련번호", "법령해석례일련번호", "ID", "id"):
                v = it.get(key)
                if v:
                    ids.append(str(v))
                    break
        return ids

    # ── 디스크 백업 ────────────────────────────────────────────────────

    def dump_raw(self, payload: dict[str, Any], out_path: Path) -> None:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)

    def iter_ids(
        self,
        target: TargetType,
        query: str,
        *,
        max_count: int = 50,
        display: int = 20,
    ) -> Iterable[str]:
        """검색 결과를 페이지네이션하며 일련번호를 yield."""
        seen: set[str] = set()
        page = 1
        while len(seen) < max_count:
            data = self.search(target, query, display=display, page=page)
            ids = self.extract_ids(data, target)
            if not ids:
                return
            for i in ids:
                if i in seen:
                    continue
                seen.add(i)
                yield i
                if len(seen) >= max_count:
                    return
            page += 1
