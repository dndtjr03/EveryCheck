"""법제처 raw JSON을 검색용 청크로 분리.

법제처 lawService.do 응답 키 구조 (실제):
  - 판례:   {"PrecService": {판시사항, 판결요지, 사건명, 사건번호, 법원명, 선고일자,
                              참조조문, 판례내용, 판례정보일련번호, ...}}
  - 해석례: {"ExpcService": {안건명, 안건번호, 질의요지, 회답, 이유,
                              해석기관명, 해석일자, 법령해석례일련번호, ...}}
  - 법령:   검색 실패 시 {"Law": "일치하는 법령이 없습니다."}
            정상 응답 구조는 실제 raw 수집 후 추가 매핑 예정.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Iterable


@dataclass
class Chunk:
    chunk_id: str
    text: str
    metadata: dict[str, Any] = field(default_factory=dict)


_SOURCE_URL = "https://www.law.go.kr"


def _safe_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _strip_html(text: str) -> str:
    """간단한 HTML 태그 제거. <br/>, <p>, <span> 등."""
    if not text:
        return ""
    return re.sub(r"<[^>]+>", " ", text).strip()


# ── 법령 (law) ─────────────────────────────────────────────────────────────


def chunk_law(raw: dict[str, Any]) -> list[Chunk]:
    """법령 본문 응답을 조 단위로 청크화.

    법령 응답 구조는 응답 유형(현행/개정/연혁)에 따라 다양함. 검색이 실패하면
    {"Law": "..."} 같이 문자열만 들어 있을 수 있으므로 가드.
    """
    root = raw.get("Law") or raw.get("법령") or raw
    if isinstance(root, str):
        # 검색 실패 메시지
        return []
    if isinstance(root, list) and root:
        root = root[0]
    if not isinstance(root, dict):
        return []

    basic = root.get("기본정보", {}) or root
    law_name = _safe_str(basic.get("법령명_한글") or basic.get("법령명")
                          or root.get("법령명"))
    law_id = _safe_str(basic.get("법령ID") or root.get("법령ID")
                       or root.get("법령일련번호"))
    promulgation = _safe_str(basic.get("공포일자"))
    enforce = _safe_str(basic.get("시행일자"))

    body = root.get("조문", {}) or {}
    articles = body.get("조문단위") or body.get("조문") or []
    if isinstance(articles, dict):
        articles = [articles]

    chunks: list[Chunk] = []
    for art in articles:
        if not isinstance(art, dict):
            continue
        article_no = _safe_str(art.get("조문번호"))
        title = _safe_str(art.get("조문제목"))
        content = _safe_str(art.get("조문내용"))

        parts: list[str] = []
        if title:
            parts.append(f"제{article_no}조 {title}" if article_no else title)
        elif article_no:
            parts.append(f"제{article_no}조")
        if content:
            parts.append(_strip_html(content))

        # 항·호 내용 합치기
        for sub_key in ("항", "호"):
            sub = art.get(sub_key)
            if isinstance(sub, list):
                for s in sub:
                    if isinstance(s, dict):
                        parts.append(_strip_html(
                            _safe_str(s.get("항내용") or s.get("호내용"))
                        ))
            elif isinstance(sub, dict):
                parts.append(_strip_html(
                    _safe_str(sub.get("항내용") or sub.get("호내용"))
                ))

        text = "\n".join(p for p in parts if p).strip()
        if not text:
            continue

        cid = f"law:{law_id}:art{article_no}"
        chunks.append(
            Chunk(
                chunk_id=cid,
                text=text,
                metadata={
                    "source_type": "law",
                    "law_name": law_name,
                    "article_no": f"제{article_no}조" if article_no else "",
                    "promulgation_date": promulgation,
                    "enforce_date": enforce,
                    "source_url": f"{_SOURCE_URL}/lsInfoP.do?lsiSeq={law_id}"
                    if law_id else "",
                },
            )
        )

    return chunks


# ── 판례 (prec) ────────────────────────────────────────────────────────────


def chunk_precedent(raw: dict[str, Any]) -> list[Chunk]:
    """판례 본문 (PrecService) → 판시사항 + 판결요지 + 참조조문을 묶어 1 chunk."""
    root = raw.get("PrecService") or raw.get("판례") or raw
    if isinstance(root, list) and root:
        root = root[0]
    if not isinstance(root, dict):
        return []

    case_no = _safe_str(root.get("사건번호"))
    case_name = _safe_str(root.get("사건명"))
    court = _safe_str(root.get("법원명"))
    decision_date = _safe_str(root.get("선고일자"))
    case_type = _safe_str(root.get("사건종류명"))
    prec_id = _safe_str(root.get("판례정보일련번호") or root.get("판례일련번호"))

    issue = _strip_html(_safe_str(root.get("판시사항")))
    summary = _strip_html(_safe_str(root.get("판결요지")))
    refs = _strip_html(_safe_str(root.get("참조조문")))

    # 의미 있는 텍스트가 하나도 없으면 스킵
    if not (issue or summary or refs):
        return []

    body_parts: list[str] = []
    if court or case_no or case_name:
        body_parts.append(f"[{court} {case_no} {case_name}]".strip())
    if issue:
        body_parts.append(f"[판시사항] {issue}")
    if summary:
        body_parts.append(f"[판결요지] {summary}")
    if refs:
        body_parts.append(f"[참조조문] {refs}")

    text = "\n".join(body_parts).strip()
    return [
        Chunk(
            chunk_id=f"prec:{prec_id or case_no}",
            text=text,
            metadata={
                "source_type": "precedent",
                "case_no": case_no,
                "case_name": case_name,
                "court": court,
                "case_type": case_type,
                "decision_date": decision_date,
                "source_url": f"{_SOURCE_URL}/precInfoP.do?precSeq={prec_id}"
                if prec_id else "",
            },
        )
    ]


# ── 해석례 (expc) ──────────────────────────────────────────────────────────


def chunk_interpretation(raw: dict[str, Any]) -> list[Chunk]:
    """법령해석례 본문 (ExpcService) → 안건명 + 질의요지 + 회답 + 이유 묶어 1 chunk."""
    root = raw.get("ExpcService") or raw.get("법령해석례") or raw
    if isinstance(root, list) and root:
        root = root[0]
    if not isinstance(root, dict):
        return []

    title = _safe_str(root.get("안건명") or root.get("해석례명"))
    case_no = _safe_str(root.get("안건번호"))
    expc_id = _safe_str(root.get("법령해석례일련번호"))
    interp_org = _safe_str(root.get("해석기관명"))
    interp_date = _safe_str(root.get("해석일자"))
    question = _strip_html(_safe_str(root.get("질의요지")))
    answer = _strip_html(_safe_str(root.get("회답")))
    reason = _strip_html(_safe_str(root.get("이유")))

    if not (question or answer or reason):
        return []

    body_parts: list[str] = []
    if title:
        body_parts.append(f"[해석례] {title}")
    if case_no:
        body_parts.append(f"안건번호: {case_no}")
    if question:
        body_parts.append(f"질의: {question}")
    if answer:
        body_parts.append(f"회답: {answer}")
    if reason:
        body_parts.append(f"이유: {reason}")

    text = "\n".join(body_parts).strip()
    return [
        Chunk(
            chunk_id=f"expc:{expc_id or case_no}",
            text=text,
            metadata={
                "source_type": "interpretation",
                "title": title,
                "case_no": case_no,
                "interpret_org": interp_org,
                "interpret_date": interp_date,
                "source_url": f"{_SOURCE_URL}/expcInfoP.do?expcSeq={expc_id}"
                if expc_id else "",
            },
        )
    ]


# ── 원상복구비 단가 (repair_price) ────────────────────────────────────────


def _fmt_won(value: int) -> str:
    return f"{value:,}원"


def _slug(s: str) -> str:
    """item 이름을 chunk_id에 쓸 수 있게 단순 슬러그화."""
    s = re.sub(r"\s+", "_", s.strip())
    s = re.sub(r"[^\w가-힣()/+*-]", "", s)
    return s[:40] or "item"


# LH 자료는 공식 용어("도 배", "타 일")만 적혀 있어 일반인 질의("벽지", "타일",
# "도어락")와 임베딩 매칭이 약함. item 이름에 부분 일치하면 관련 어휘를 청크
# 텍스트에 덧붙여 검색 적중률을 높인다.
_ITEM_ALIASES: list[tuple[str, str]] = [
    ("도 배", "벽지 도배지 wallpaper"),
    ("도배", "벽지 도배지"),
    ("장 판", "바닥재 룸카펫 비닐장판"),
    ("장판", "바닥재 룸카펫 비닐장판"),
    ("도어록", "도어락 잠금장치 손잡이"),
    ("콘센트", "전기 콘센트 멀티탭"),
    ("스위치", "전기 스위치 등 점등"),
    ("양변기", "변기 좌변기 화장실"),
    ("세면기", "세면대 세면볼"),
    ("출입문", "문 도어"),
    ("현관문", "현관문 정문 도어"),
    ("싱크", "부엌 주방 싱크대"),
    ("방충망", "방충망 모기장"),
    ("타 일", "타일 욕실타일"),
    ("타일", "타일 욕실타일"),
    ("벽체", "벽 벽면"),
    ("천정", "천장 천정"),
    ("바닥", "마루 마룻바닥"),
    ("샤워", "샤워기 샤워실"),
    ("렌지후드", "후드 환풍기 가스레인지"),
    ("석고보드", "석고 보드 벽체"),
    ("방충망", "방충망 모기장"),
    ("도 장", "페인트 도색 도장"),
    ("도장", "페인트 도색 도장"),
]


def _aliases_for(item: str, category: str) -> str:
    matched: list[str] = []
    haystack = f"{item} {category}"
    for key, alias in _ITEM_ALIASES:
        if key in haystack:
            matched.append(alias)
    # 중복 단어 제거 (정렬 유지)
    seen = set()
    words: list[str] = []
    for token in " ".join(matched).split():
        if token not in seen:
            seen.add(token)
            words.append(token)
    return " ".join(words)


def chunk_repair_price(raw: dict[str, Any]) -> list[Chunk]:
    """LH 2023 퇴거세대 원상복구비 표준단가표 JSON → ChromaDB 청크.

    raw 구조 (Gemini Vision OCR 산출물):
        {
          "source": "LH 2023 퇴거세대 원상복구비 표준단가표",
          "pages": {
            "영구임대": [{category, item, unit_price, unit}, ...],
            "국민임대": [...],
            "공공임대": [...],
            "산출예시_장판": {example: true, subject, scenario, formula_note, rows: [...]}
          }
        }

    적재 전략:
      - 임대유형 3종 단가가 동일한 경우가 다수 → (category, item) 단위로 단가 동일
        여부 검사 후 1개 청크로 통합. 다르면 임대유형별 분리.
      - 산출예시(감가상각 공식 포함) → 별도 1청크. 사용자 질의 "감가상각",
        "수선주기", "장판 비용" 같은 케이스를 잡기 위함.
    """
    source = _safe_str(raw.get("source")) or "LH 퇴거세대 원상복구비 표준단가표"
    pages = raw.get("pages") or {}

    contract_types = ("영구임대", "국민임대", "공공임대")

    # (category, item) -> {contract_type: (unit_price, unit)}
    grouped: dict[tuple[str, str], dict[str, tuple[int, str]]] = {}
    for ct in contract_types:
        items = pages.get(ct) or []
        if not isinstance(items, list):
            continue
        for it in items:
            if not isinstance(it, dict):
                continue
            cat = _safe_str(it.get("category"))
            name = _safe_str(it.get("item"))
            price = it.get("unit_price")
            unit = _safe_str(it.get("unit")) or "/개"
            if not (cat and name and isinstance(price, (int, float))):
                continue
            key = (cat, name)
            grouped.setdefault(key, {})[ct] = (int(price), unit)

    chunks: list[Chunk] = []

    for (cat, name), per_type in sorted(grouped.items()):
        prices = {v[0] for v in per_type.values()}
        applicable = sorted(per_type.keys())  # 임대유형 표시
        applicable_str = ", ".join(applicable)

        aliases = _aliases_for(name, cat)
        alias_line = f"관련 어휘: {aliases}.\n" if aliases else ""

        if len(prices) == 1:
            # 단가 동일 → 1청크로 통합
            price, unit = next(iter(per_type.values()))
            text = (
                f"[{cat}] {name} — LH 퇴거세대 원상복구비 표준 단가 "
                f"{_fmt_won(price)}{unit}.\n"
                f"{alias_line}"
                f"적용 임대유형: {applicable_str} (단가 동일).\n"
                f"임대주택 퇴거 시 원상회복 비용 산출 항목. "
                f"산출방식: 단가 × 수량(또는 면적) → 보수비용 → "
                f"감가상각률(경과연수/수선주기)만큼 차감 → 최종 임차인 부과비용.\n"
                f"출처: {source}."
            )
            cid = f"repair:lh2023:{_slug(cat)}:{_slug(name)}"
            chunks.append(
                Chunk(
                    chunk_id=cid,
                    text=text,
                    metadata={
                        "source_type": "repair_price",
                        "source": source,
                        "year": 2023,
                        "issuer": "LH",
                        "category": cat,
                        "item": name,
                        "unit_price": price,
                        "unit": unit,
                        "contract_types": applicable_str,
                    },
                )
            )
        else:
            # 임대유형별 단가가 다름 → 임대유형별 분리 청크
            for ct, (price, unit) in sorted(per_type.items()):
                text = (
                    f"[{cat}] {name} — LH {ct} 원상복구비 단가 "
                    f"{_fmt_won(price)}{unit}.\n"
                    f"{alias_line}"
                    f"적용 임대유형: {ct}.\n"
                    f"산출방식: 단가 × 수량(또는 면적) → 보수비용 → "
                    f"감가상각률(경과연수/수선주기) 차감 → 최종 부과비용.\n"
                    f"출처: {source}."
                )
                cid = f"repair:lh2023:{_slug(ct)}:{_slug(cat)}:{_slug(name)}"
                chunks.append(
                    Chunk(
                        chunk_id=cid,
                        text=text,
                        metadata={
                            "source_type": "repair_price",
                            "source": source,
                            "year": 2023,
                            "issuer": "LH",
                            "category": cat,
                            "item": name,
                            "unit_price": price,
                            "unit": unit,
                            "contract_types": ct,
                        },
                    )
                )

    # 산출예시 + 감가상각 공식 청크
    for ex_key, ex_val in pages.items():
        if not isinstance(ex_val, dict) or not ex_val.get("example"):
            continue
        subject = _safe_str(ex_val.get("subject")) or ex_key
        scenario = _safe_str(ex_val.get("scenario"))
        formula = _safe_str(ex_val.get("formula_note"))
        rows = ex_val.get("rows") or []

        row_lines: list[str] = []
        for r in rows:
            if not isinstance(r, dict):
                continue
            part = _safe_str(r.get("part"))
            calc = _safe_str(r.get("calc"))
            area = r.get("area_m2")
            up = r.get("unit_price")
            rc = r.get("repair_cost")
            note = _safe_str(r.get("note"))
            pieces = [f"- {part}"]
            if calc:
                pieces.append(f"산식 {calc}")
            if isinstance(area, (int, float)):
                pieces.append(f"면적 {area}㎡")
            if isinstance(up, (int, float)):
                pieces.append(f"단가 {_fmt_won(int(up))}")
            if isinstance(rc, (int, float)):
                pieces.append(f"보수비용 {_fmt_won(int(rc))}")
            if note:
                pieces.append(note)
            row_lines.append(" / ".join(pieces))

        parts: list[str] = [f"[원상복구비 산출 예시 — {subject}]"]
        if scenario:
            parts.append(scenario)
        if row_lines:
            parts.append("\n".join(row_lines))
        if formula:
            parts.append(f"산출 공식 및 주석: {formula}")
        parts.append(f"출처: {source}.")
        text = "\n".join(parts).strip()

        chunks.append(
            Chunk(
                chunk_id=f"repair:lh2023:example:{_slug(subject)}",
                text=text,
                metadata={
                    "source_type": "repair_price",
                    "source": source,
                    "year": 2023,
                    "issuer": "LH",
                    "category": "산출예시",
                    "item": subject,
                    "is_example": True,
                },
            )
        )

    return chunks


# ── 정적 법령 (static_law) ────────────────────────────────────────────────


def chunk_static_laws(raw: dict[str, Any]) -> list[Chunk]:
    """정적으로 작성한 법령 JSON → ChromaDB 청크.

    법제처 OpenAPI lawService.do 본문 조회가 일치 ID를 못 잡아 적재 0건이 된
    문제를 우회. 임대차 분쟁 핵심 조문(민법 615/623/654/610·주임법·국토부
    가이드라인·통상 손모 법리)을 직접 텍스트로 임베딩한다.

    raw 구조: { "source": str, "laws": [{id, law_name, article_no, title, body, context, source_url}, ...] }
    """
    source = _safe_str(raw.get("source")) or "정적 적재 법령"
    items = raw.get("laws") or []
    if not isinstance(items, list):
        return []

    chunks: list[Chunk] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        item_id = _safe_str(it.get("id"))
        law_name = _safe_str(it.get("law_name"))
        article_no = _safe_str(it.get("article_no"))
        title = _safe_str(it.get("title"))
        body = _safe_str(it.get("body"))
        context = _safe_str(it.get("context"))
        url = _safe_str(it.get("source_url"))

        if not body and not context:
            continue

        # 검색에 잘 잡히도록 헤더 + 본문 + 해설을 한 청크에 모음.
        text_parts: list[str] = []
        head = " ".join(p for p in (law_name, article_no, title) if p).strip()
        if head:
            text_parts.append(f"[{head}]")
        if body:
            text_parts.append(body)
        if context:
            text_parts.append(f"[해설] {context}")
        text = "\n".join(text_parts).strip()

        # 메타 source_type 은 기존 precedent/interpretation 패턴과 일관되게 "law" 사용.
        # 채팅 라우터의 _RAG_MIX와 라벨 분기가 'law'를 기대함.
        chunks.append(
            Chunk(
                chunk_id=f"law:static:{item_id or _slug(head) or 'item'}",
                text=text,
                metadata={
                    "source_type": "law",
                    "law_name": law_name,
                    "article_no": article_no,
                    "title": title,
                    "source_url": url,
                    "source": source,
                    "is_static": True,
                },
            )
        )

    return chunks


# ── 통합 ──────────────────────────────────────────────────────────────────


def chunk_any(target: str, raw: dict[str, Any]) -> Iterable[Chunk]:
    if target == "law":
        return chunk_law(raw)
    if target == "prec":
        return chunk_precedent(raw)
    if target == "expc":
        return chunk_interpretation(raw)
    if target == "repair_price":
        return chunk_repair_price(raw)
    if target == "static_law":
        return chunk_static_laws(raw)
    return []
