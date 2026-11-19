from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


class User(Base):
    __tablename__ = "hollow_users"
    __table_args__ = (CheckConstraint("level IN (2, 3, 4)", name="hollow_user_level"),)

    username: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    password_hash: Mapped[str] = mapped_column(String(128))
    level: Mapped[int]
    device_id: Mapped[UUID] = mapped_column(unique=True)


class LoginSession(Base):
    __tablename__ = "hollow_sessions"

    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    username: Mapped[str] = mapped_column(ForeignKey("hollow_users.username", ondelete="CASCADE"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Contact(Base):
    __tablename__ = "hollow_contacts"

    owner: Mapped[str] = mapped_column(ForeignKey("hollow_users.username", ondelete="CASCADE"), primary_key=True)
    contact: Mapped[str] = mapped_column(ForeignKey("hollow_users.username", ondelete="CASCADE"), primary_key=True)
