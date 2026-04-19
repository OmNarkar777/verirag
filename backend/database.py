"""
database.py — Async SQLAlchemy engine, session factory, and base model.

WHY ASYNC:
- Evaluation runs can take 30-60s (RAGAS calls multiple LLM endpoints)
- Synchronous DB drivers would block the event loop during that time
- asyncpg is the fastest PostgreSQL async driver — 3-4x faster than psycopg2
  for high-concurrency workloads

WHY NOT create_all():
- We use Alembic migrations instead (see alembic/)
- create_all() is fine for prototypes but loses schema history
- Recruiters want to see you understand schema evolution in production
"""

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from backend.config import get_settings

settings = get_settings()

# pool_pre_ping: validates connections before use — handles DB restarts gracefully
# pool_size + max_overflow: tune for eval workload (mostly I/O bound, not CPU)
# echo=False in prod: SQL logging is expensive at scale
engine = create_async_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    echo=not settings.is_production,
)

# async_sessionmaker is the async equivalent of sessionmaker
# expire_on_commit=False: prevents lazy-load errors after commit in async context
# This is a critical asyncio gotcha — expired attrs trigger sync I/O
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


class Base(DeclarativeBase):
    """
    Declarative base for all ORM models.
    Using the new 2.0-style DeclarativeBase (not declarative_base())
    for better type inference with SQLAlchemy 2.x mapped_column().
    """
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    FastAPI dependency that yields a database session.

    Usage in routes:
        async def my_route(db: AsyncSession = Depends(get_db)):

    The try/finally ensures rollback on unhandled exceptions, preventing
    connection pool exhaustion from hanging transactions.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


@asynccontextmanager
async def get_db_context() -> AsyncGenerator[AsyncSession, None]:
    """
    Context manager version of get_db for use outside of FastAPI DI
    (e.g., background tasks, CLI scripts, tests).

    Usage:
        async with get_db_context() as db:
            result = await db.execute(...)
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
