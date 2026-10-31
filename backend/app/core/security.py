"""Password hashing and login-token helpers."""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from app.core.config import get_settings


# ---------- Passwords ----------

def hash_password(plain_password: str) -> str:
    """Return a bcrypt hash. The plain password is never stored."""
    # bcrypt only uses the first 72 bytes, so we pre-hash long passwords safely.
    data = _prepare(plain_password)
    return bcrypt.hashpw(data, bcrypt.gensalt(rounds=12)).decode("utf-8")


def verify_password(plain_password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(_prepare(plain_password), password_hash.encode("utf-8"))
    except ValueError:
        return False


def _prepare(password: str) -> bytes:
    raw = password.encode("utf-8")
    if len(raw) > 72:
        raw = hashlib.sha256(raw).hexdigest().encode("utf-8")
    return raw


# ---------- Tokens ----------

def _now() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(user_id: str, roles: list[str]) -> str:
    settings = get_settings()
    payload = {
        "sub": user_id,
        "roles": roles,
        "type": "access",
        "iat": _now(),
        "exp": _now() + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(user_id: str) -> tuple[str, str, datetime]:
    """Return (token, token_id, expires_at). The token id lets us revoke it later."""
    settings = get_settings()
    token_id = secrets.token_urlsafe(16)
    expires_at = _now() + timedelta(days=settings.refresh_token_days)
    payload = {"sub": user_id, "type": "refresh", "jti": token_id, "iat": _now(), "exp": expires_at}
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, token_id, expires_at


def decode_token(token: str, expected_type: str) -> dict:
    """Decode and check a token. Raises jwt.InvalidTokenError when invalid or expired."""
    settings = get_settings()
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    if payload.get("type") != expected_type:
        raise jwt.InvalidTokenError("Wrong token type")
    return payload


def hash_token_id(token_id: str) -> str:
    """Refresh token ids are stored hashed, like passwords."""
    return hashlib.sha256(token_id.encode("utf-8")).hexdigest()
