import asyncio
from datetime import datetime, timedelta, timezone

from app.routers.medicines import allergy_match
from tests.conftest import auth_header

PANADOL = {"name": "Panadol", "salt": "Paracetamol", "strength": "500 mg", "form": "tablet",
           "times": ["20:00", "08:00"], "instructions": "after food"}


def test_allergy_matching_rules():
    assert allergy_match(["Penicillin"], "Amoxil", "Amoxicillin") is None
    assert allergy_match(["Penicillin"], "Pen-V", "Phenoxymethylpenicillin") == "Penicillin"
    assert allergy_match(["Aspirin"], "Disprin", "Aspirin") == "Aspirin"
    assert allergy_match(["Peanuts"], "Panadol", "Paracetamol") is None
    assert allergy_match([], "Panadol", "Paracetamol") is None


def test_add_list_and_times_sorted(registered):
    client, tokens = registered
    h = auth_header(tokens)
    r = client.post("/medicines", headers=h, json=PANADOL)
    assert r.status_code == 201, r.text
    assert r.json()["times"] == ["08:00", "20:00"]
    assert [m["name"] for m in client.get("/medicines", headers=h).json()] == ["Panadol"]


def test_invalid_time_rejected(registered):
    client, tokens = registered
    r = client.post("/medicines", headers=auth_header(tokens), json={**PANADOL, "times": ["25:00"]})
    assert r.status_code == 422


def test_allergy_warning_requires_confirmation(registered):
    client, tokens = registered
    h = auth_header(tokens)
    client.patch("/profile", headers=h, json={"allergies": ["Aspirin"]})
    disprin = {**PANADOL, "name": "Disprin", "salt": "Aspirin"}
    r = client.post("/medicines", headers=h, json=disprin)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "allergy_warning"
    assert "Aspirin" in r.json()["error"]["message"]
    r2 = client.post("/medicines", headers=h, json={**disprin, "confirm_allergy_override": True})
    assert r2.status_code == 201
    assert "Possible allergy match" in r2.json()["allergy_warning"]


def test_medicines_are_private(registered):
    client, tokens_a = registered
    med = client.post("/medicines", headers=auth_header(tokens_a), json=PANADOL).json()
    tokens_b = client.post("/auth/register", json={"full_name": "B User", "email": "b@example.com",
                                                   "password": "Secure123", "accepted_terms": True}).json()
    assert client.get("/medicines", headers=auth_header(tokens_b)).json() == []
    assert client.post(f"/medicines/{med['id']}/stop", headers=auth_header(tokens_b)).status_code == 404


def test_stop_keeps_history(registered):
    client, tokens = registered
    h = auth_header(tokens)
    med = client.post("/medicines", headers=h, json=PANADOL).json()
    assert client.post(f"/medicines/{med['id']}/stop", headers=h).json()["active"] is False
    assert client.get("/medicines", headers=h).json() == []
    assert len(client.get("/medicines?include_stopped=true", headers=h).json()) == 1


def _offset_for(local_hhmm: str) -> int:
    """Pick a tz offset so that the user's local time right now is about local_hhmm."""
    now = datetime.now(timezone.utc)
    h, m = map(int, local_hhmm.split(":"))
    target = now.replace(hour=h, minute=m, second=0, microsecond=0)
    diff = int((target - now).total_seconds() // 60)
    return ((diff + 720) % 1440) - 720


def test_today_schedule_missed_and_taken(registered):
    client, tokens = registered
    h = auth_header(tokens)
    med = client.post("/medicines", headers=h, json={**PANADOL, "times": ["08:00", "12:00", "22:00"]}).json()
    off = _offset_for("12:10")  # local time ~12:10
    doses = {d["time"]: d["status"] for d in client.get(f"/medicines/today?tz_offset_minutes={off}", headers=h).json()}
    assert doses == {"08:00": "missed", "12:00": "due", "22:00": "upcoming"}
    # one notification for the missed dose, even if checked twice
    client.get(f"/medicines/today?tz_offset_minutes={off}", headers=h)
    notes = client.get("/notifications", headers=h).json()
    assert [n["title"] for n in notes] == ["Missed dose"]

    r = client.post(f"/medicines/{med['id']}/intake?tz_offset_minutes={off}", headers=h,
                    json={"time": "12:00", "status": "taken"})
    assert r.json()["status"] == "taken"
    doses = {d["time"]: d["status"] for d in client.get(f"/medicines/today?tz_offset_minutes={off}", headers=h).json()}
    assert doses["12:00"] == "taken"
    adherence = client.get("/medicines/adherence", headers=h).json()
    assert adherence["taken"] == 1 and adherence["missed"] == 1 and adherence["percent_taken"] == 50


def test_intake_at_unscheduled_time_rejected(registered):
    client, tokens = registered
    h = auth_header(tokens)
    med = client.post("/medicines", headers=h, json=PANADOL).json()
    r = client.post(f"/medicines/{med['id']}/intake", headers=h, json={"time": "13:00", "status": "taken"})
    assert r.status_code == 422
