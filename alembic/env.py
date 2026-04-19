"""alembic/env.py â€” Async Alembic migration environment."""
import asyncio
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine
from dotenv import load_dotenv

load_dotenv()

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

from backend.database import Base          # noqa: E402
from backend.models import EvalRun, EvalCase, PipelineDocument  # noqa: E402, F401

target_metadata = Base.metadata


def get_url() -> str:
    url = os.getenv("DATABASE_URL", "postgresql+asyncpg://verirag:verirag_secret@localhost:5432/verirag")
    if not url.startswith("postgresql+asyncpg"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    return url


def run_migrations_offline() -> None:
    context.configure(
        url=get_url(), target_metadata=target_metadata,
        literal_binds=True, dialect_opts={"paramstyle": "named"},
        include_schemas=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata,
                      include_schemas=True, compare_server_default=True)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = create_async_engine(get_url())
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


# IMPORTANT: always guard with is_offline_mode() â€” never run at import time
if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())