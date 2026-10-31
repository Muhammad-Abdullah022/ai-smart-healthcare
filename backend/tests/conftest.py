"""Test setup: uses an in-memory fake MongoDB, so tests never touch Atlas."""
import os

# Test-only settings (not real secrets).
os.environ["MONGODB_URI"] = "mongodb://localhost:27017"
os.environ["MONGODB_DB"] = "test_db"
os.environ["JWT_SECRET"] = "test-secret-that-is-long-enough-for-hs256-0123456789"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from mongomock_motor import AsyncMongoMockClient  # noqa: E402

from app.main import create_app  # noqa: E402


@pytest.fixture
def client():
    app = create_app()
    app.state.db = AsyncMongoMockClient(tz_aware=True)["test_db"]
    with TestClient(app) as test_client:
        yield test_client


VALID_USER = {
    "full_name": "Ayesha Khan",
    "email": "ayesha@example.com",
    "password": "Secure123",
    "accepted_terms": True,
}


@pytest.fixture
def registered(client):
    """Register a user and return (client, tokens)."""
    response = client.post("/auth/register", json=VALID_USER)
    assert response.status_code == 201, response.text
    return client, response.json()


def auth_header(tokens: dict) -> dict:
    return {"Authorization": f"Bearer {tokens['access_token']}"}
