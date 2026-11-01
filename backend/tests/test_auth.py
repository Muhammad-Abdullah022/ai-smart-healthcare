import asyncio

from tests.conftest import VALID_USER, auth_header


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_register_returns_tokens_and_stores_only_hash(client):
    response = client.post("/auth/register", json=VALID_USER)
    assert response.status_code == 201
    body = response.json()
    assert body["access_token"] and body["refresh_token"]

    stored = asyncio.run(client.app.state.db.users.find_one({"email": VALID_USER["email"]}))
    assert stored["password_hash"] != VALID_USER["password"]
    assert "password" not in stored


def test_register_duplicate_email_rejected(registered):
    client, _ = registered
    response = client.post("/auth/register", json={**VALID_USER, "email": "AYESHA@example.com"})
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "email_taken"


def test_register_validation_errors(client):
    weak = client.post("/auth/register", json={**VALID_USER, "password": "password"})
    assert weak.status_code == 422
    assert weak.json()["error"]["code"] == "validation_error"
    no_terms = client.post("/auth/register", json={**VALID_USER, "accepted_terms": False})
    assert no_terms.status_code == 422
    bad_email = client.post("/auth/register", json={**VALID_USER, "email": "not-an-email"})
    assert bad_email.status_code == 422


def test_login_success_and_me(registered):
    client, _ = registered
    response = client.post("/auth/login", json={"email": VALID_USER["email"], "password": "Secure123"})
    assert response.status_code == 200
    me = client.get("/auth/me", headers=auth_header(response.json()))
    assert me.status_code == 200
    assert me.json()["email"] == VALID_USER["email"]
    assert me.json()["roles"] == ["patient"]


def test_login_wrong_password_and_unknown_email_look_the_same(registered):
    client, _ = registered
    wrong = client.post("/auth/login", json={"email": VALID_USER["email"], "password": "Wrong1234"})
    unknown = client.post("/auth/login", json={"email": "nobody@example.com", "password": "Wrong1234"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_me_requires_login(client):
    assert client.get("/auth/me").status_code == 401
    bad = client.get("/auth/me", headers={"Authorization": "Bearer not-a-token"})
    assert bad.status_code == 401


def test_refresh_rotates_token(registered):
    client, tokens = registered
    first = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert first.status_code == 200
    # The old refresh token can't be used a second time.
    again = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert again.status_code == 401


def test_logout_revokes_refresh_token(registered):
    client, tokens = registered
    assert client.post("/auth/logout", json={"refresh_token": tokens["refresh_token"]}).status_code == 204
    after = client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert after.status_code == 401


def test_access_token_cannot_be_used_as_refresh(registered):
    client, tokens = registered
    response = client.post("/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert response.status_code == 401


def test_audit_events_recorded(registered):
    client, _ = registered
    client.post("/auth/login", json={"email": VALID_USER["email"], "password": "Wrong1234"})
    actions = asyncio.run(client.app.state.db.audit_events.distinct("action"))
    assert "user.register" in actions and "user.login_failed" in actions


def test_cors_allows_flutter_web_on_localhost(client):
    response = client.options(
        "/auth/login",
        headers={"Origin": "http://localhost:54321", "Access-Control-Request-Method": "POST"},
    )
    assert response.headers.get("access-control-allow-origin") == "http://localhost:54321"


def test_cors_blocks_unknown_sites(client):
    response = client.options(
        "/auth/login",
        headers={"Origin": "https://evil.example.com", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in response.headers
