import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


class Base(DeclarativeBase):
    pass


def database_url() -> str:
    url = os.getenv("DATABASE_URL", "")
    if not url or "PROJECT_REF" in url:
        raise RuntimeError("Set DATABASE_URL in the root .env using the Supabase Session Pooler URI.")
    return url.replace("postgresql://", "postgresql+psycopg://", 1) if url.startswith("postgresql://") else url


def make_engine():
    return create_engine(database_url(), pool_pre_ping=True)
