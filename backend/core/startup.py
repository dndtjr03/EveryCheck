"""애플리케이션 startup 훅 — 감사 로그 init + RAG 워밍업."""

import logging
import threading

from fastapi import FastAPI

from security_audit import init_security_audit_logger


def install_startup_hooks(app: FastAPI) -> None:
    """FastAPI startup 이벤트에 초기화 훅을 등록한다."""

    @app.on_event("startup")
    def _init_audit_log() -> None:
        init_security_audit_logger()

    @app.on_event("startup")
    def _warmup_rag() -> None:
        """RAG 임베딩 모델·ChromaDB를 백그라운드에서 미리 로드.

        첫 채팅 요청 시 ko-sroberta 모델(약 400MB)을 처음 메모리에 올리느라
        1~3초가 추가로 걸리는 현상을 제거하기 위함. 메인 startup을 블로킹하지
        않도록 별도 스레드에서 dummy query를 1회 실행하고, 실패해도 채팅은
        on-demand 로드로 계속 동작한다.
        """
        log = logging.getLogger("rag.warmup")

        def _warm() -> None:
            try:
                from rag import get_default_index

                idx = get_default_index()
                idx.query("워밍업", n_results=1)
                log.info("RAG warmup done - chunks=%d", idx.count())
            except Exception as exc:  # noqa: BLE001
                log.warning("RAG warmup skipped (will load on first chat): %s", exc)

        threading.Thread(target=_warm, name="rag-warmup", daemon=True).start()
