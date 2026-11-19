import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete
from sqlalchemy.orm import Session

from .models import LoginSession


def password_hash(password: str, salt: bytes | None = None) -> str:
    salt = salt if salt is not None else secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"{salt.hex()}:{digest.hex()}"


DUMMY_HASH = password_hash("unused-password")


def verify_password(password: str, stored: str) -> bool:
    salt, _ = stored.split(":")
    return hmac.compare_digest(password_hash(password, bytes.fromhex(salt)), stored)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_session(db: Session, username: str) -> str:
    now = datetime.now(timezone.utc)
    db.execute(delete(LoginSession).where(LoginSession.username == username, LoginSession.expires_at <= now))
    token = secrets.token_urlsafe(32)
    db.add(LoginSession(token_hash=token_hash(token), username=username, expires_at=now + timedelta(days=30)))
    return token
