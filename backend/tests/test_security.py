import jwt
import pytest

from app.core.config import Settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)


def test_password_is_hashed_not_plain():
    hashed = hash_password("Secure123")
    assert hashed != "Secure123"
    assert hashed.startswith("$2")  # bcrypt format
    assert verify_password("Secure123", hashed)
    assert not verify_password("Wrong123", hashed)


def test_long_password_supported():
    long_password = "a1" * 60  # 120 characters, longer than bcrypt's 72-byte limit
    hashed = hash_password(long_password)
    assert verify_password(long_password, hashed)
    assert not verify_password(long_password[:-1], hashed)


def test_access_token_round_trip():
    token = create_access_token("user123", ["patient"])
    payload = decode_token(token, expected_type="access")
    assert payload["sub"] == "user123"
    assert payload["roles"] == ["patient"]


def test_refresh_token_rejected_as_access_token():
    token, _, _ = create_refresh_token("user123")
    with pytest.raises(jwt.InvalidTokenError):
        decode_token(token, expected_type="access")


def test_tampered_token_rejected():
    token = create_access_token("user123", ["patient"])
    with pytest.raises(jwt.InvalidTokenError):
        decode_token(token[:-2] + "xx", expected_type="access")


def test_short_jwt_secret_refused():
    with pytest.raises(ValueError):
        Settings(mongodb_uri="mongodb://x", jwt_secret="too-short")


def test_memory_db_mode_starts_without_atlas(monkeypatch):
    from fastapi.testclient import TestClient

    from app.core.config import get_settings
    from app.main import create_app

    monkeypatch.setenv("USE_MEMORY_DB", "true")
    monkeypatch.setenv("MONGODB_URI", "")
    get_settings.cache_clear()
    try:
        with TestClient(create_app()) as client:
            assert client.post("/auth/register", json={
                "full_name": "Test User", "email": "t@example.com",
                "password": "Secure123", "accepted_terms": True}).status_code == 201
    finally:
        get_settings.cache_clear()
