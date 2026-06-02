"""Alembic migration environment for EveryCheck backend.

Resolves the database URL from (in order):
1. ``config.get_settings().database_url`` if a ``config`` module is available.
2. ``DATABASE_URL`` environment variable (loaded from project-root ``.env``).

Both online and offline migration modes are supported. ``compare_type`` and
``compare_server_default`` are enabled so autogenerate detects column-type
and default changes — not just adds/drops.
"""

from __future__ import annotations

import os
import sys
from logging.config import fileConfig
from pathlib import Path

from sqlalchemy import engine_from_config, pool

from alembic import context

# ---------------------------------------------------------------------------
# Path setup — make ``backend/`` importable so ``database``/``models`` resolve.
# ---------------------------------------------------------------------------
BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# ---------------------------------------------------------------------------
# Load environment variables from the project-root .env (one level above backend/).
# ---------------------------------------------------------------------------
try:
    from dotenv import load_dotenv

    _env_path = BACKEND_DIR.parent / ".env"
    if _env_path.exists():
        load_dotenv(_env_path)
except Exception:
    # dotenv is optional at this stage — env vars may already be set by the shell.
    pass

# ---------------------------------------------------------------------------
# Import the SQLAlchemy Base AFTER sys.path is set up. Importing ``models``
# is required so every ORM class registers itself onto ``Base.metadata`` —
# without this, autogenerate would see an empty metadata.
# ---------------------------------------------------------------------------
from database import Base  # noqa: E402
import models  # noqa: E402,F401  (side-effect: registers tables on Base.metadata)

target_metadata = Base.metadata

# ---------------------------------------------------------------------------
# Alembic Config object — values from alembic.ini.
# ---------------------------------------------------------------------------
config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)


def _resolve_database_url() -> str:
    """Pick the DB URL from config.get_settings() first, then DATABASE_URL env."""
    url: str | None = None
    try:
        from config import get_settings  # type: ignore

        url = getattr(get_settings(), "database_url", None)
    except Exception:
        url = None

    if not url:
        url = os.getenv("DATABASE_URL")

    if not url:
        raise RuntimeError(
            "Database URL not resolved. Set DATABASE_URL in the project-root .env "
            "or provide config.get_settings().database_url."
        )
    return url


# Inject the resolved URL into the Alembic config so engine_from_config picks it up.
config.set_main_option("sqlalchemy.url", _resolve_database_url())


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode — emits SQL to stdout, no DB connection."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode — connects to the DB via Engine."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
