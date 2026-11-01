import asyncio

from tests.conftest import VALID_USER, auth_header


def test_login_rate_limited_after_10_attempts(registered):
    client, _ = registered
    bad = {"email": VALID_USER["email"], "password": "Wrong1234"}
    codes = [client.post("/auth/login", json=bad).status_code for _ in range(11)]
    assert codes[:10] == [401] * 10
    assert codes[10] == 429
    assert client.post("/auth/login", json=bad).json()["error"]["code"] == "rate_limited"


def test_patient_cannot_use_admin_endpoint(registered):
    client, tokens = registered
    response = client.get("/admin/stats", headers=auth_header(tokens))
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "forbidden"


def test_admin_can_use_admin_endpoint(registered):
    client, tokens = registered
    db = client.app.state.db
    asyncio.run(db.users.update_one({"email": VALID_USER["email"]}, {"$set": {"roles": ["admin"]}}))
    response = client.get("/admin/stats", headers=auth_header(tokens))
    assert response.status_code == 200
    assert response.json()["users"] == 1


def test_consents_default_off_and_history_kept(registered):
    client, tokens = registered
    h = auth_header(tokens)
    states = {c["category"]: c["granted"] for c in client.get("/consents", headers=h).json()}
    assert states["mental_health"] is False and len(states) == 6
    client.post("/consents", headers=h, json={"category": "mental_health", "granted": True})
    client.post("/consents", headers=h, json={"category": "mental_health", "granted": False})
    client.post("/consents", headers=h, json={"category": "mental_health", "granted": True})
    states = {c["category"]: c["granted"] for c in client.get("/consents", headers=h).json()}
    assert states["mental_health"] is True
    history = asyncio.run(client.app.state.db.consents.count_documents({"category": "mental_health"}))
    assert history == 3


def test_invalid_consent_category(registered):
    client, tokens = registered
    r = client.post("/consents", headers=auth_header(tokens), json={"category": "spying", "granted": True})
    assert r.status_code == 422


def test_notifications_are_private_and_markable(registered):
    from app.routers.notifications import notify

    client, tokens_a = registered
    tokens_b = client.post("/auth/register", json={**VALID_USER, "email": "b@example.com"}).json()
    db = client.app.state.db
    user_a = asyncio.run(db.users.find_one({"email": VALID_USER["email"]}))
    asyncio.run(notify(db, user_a["_id"], "test", "Hello", "World"))

    items = client.get("/notifications", headers=auth_header(tokens_a)).json()
    assert len(items) == 1 and items[0]["read"] is False
    assert client.get("/notifications", headers=auth_header(tokens_b)).json() == []
    # B cannot mark A's notification
    assert client.post(f"/notifications/{items[0]['id']}/read", headers=auth_header(tokens_b)).status_code == 404
    assert client.post(f"/notifications/{items[0]['id']}/read", headers=auth_header(tokens_a)).json()["read"] is True


def test_notification_preferences_saved(registered):
    client, tokens = registered
    h = auth_header(tokens)
    assert client.get("/profile", headers=h).json()["notification_prefs"]["medicine_reminders"] is True
    body = client.patch("/profile", headers=h, json={"notification_prefs": {
        "medicine_reminders": False, "appointments": True, "health_tips": True}}).json()
    assert body["notification_prefs"] == {"medicine_reminders": False, "appointments": True, "health_tips": True}
