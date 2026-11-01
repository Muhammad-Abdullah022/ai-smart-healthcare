import pytest

from app.routers.mental import score
from tests.conftest import auth_header


def _consent(client, tokens):
    client.post("/consents", headers=auth_header(tokens), json={"category": "mental_health", "granted": True})


@pytest.mark.parametrize("instrument,answers,expected", [
    ("phq9", [0] * 9, (0, "minimal")),
    ("phq9", [1] * 9, (9, "mild")),
    ("phq9", [2, 2, 2, 2, 2, 0, 0, 0, 0], (10, "moderate")),
    ("phq9", [3, 3, 3, 3, 3, 2, 2, 0, 0], (19, "moderately severe")),
    ("phq9", [3] * 9, (27, "severe")),
    ("gad7", [0, 0, 0, 0, 1, 1, 2], (4, "minimal")),
    ("gad7", [2] * 7, (14, "moderate")),
    ("gad7", [3] * 7, (21, "severe")),
])
def test_published_scoring_bands(instrument, answers, expected):
    assert score(instrument, answers) == expected


def test_crisis_resources_need_no_login(client):
    body = client.get("/mental/crisis-resources").json()
    assert body["emergency"][0]["phone"] == "1122"
    assert any("Rozan" in s["name"] for s in body["support"])


def test_screening_requires_consent(registered):
    client, tokens = registered
    r = client.post("/mental/screenings", headers=auth_header(tokens), json={"instrument": "gad7", "answers": [1] * 7})
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "consent_required"


def test_screening_scored_and_saved(registered):
    client, tokens = registered
    _consent(client, tokens)
    r = client.post("/mental/screenings", headers=auth_header(tokens), json={"instrument": "gad7", "answers": [2] * 7})
    assert r.status_code == 201
    body = r.json()
    assert body["score"] == 14 and body["severity"] == "moderate" and body["max_score"] == 21
    assert body["crisis"] is False and "not a diagnosis" in body["note"]
    assert len(client.get("/mental/screenings", headers=auth_header(tokens)).json()) == 1


def test_self_harm_answer_always_shows_crisis_support(registered):
    client, tokens = registered
    _consent(client, tokens)
    answers = [0] * 8 + [1]  # low total score, but question 9 answered "Several days"
    body = client.post("/mental/screenings", headers=auth_header(tokens),
                       json={"instrument": "phq9", "answers": answers}).json()
    assert body["severity"] == "minimal"
    assert body["crisis"] is True
    assert body["crisis_resources"]["emergency"][0]["phone"] == "1122"


@pytest.mark.parametrize("answers", [[1] * 8, [4] + [0] * 8, [-1] + [0] * 8])
def test_invalid_answers_rejected(registered, answers):
    client, tokens = registered
    _consent(client, tokens)
    r = client.post("/mental/screenings", headers=auth_header(tokens), json={"instrument": "phq9", "answers": answers})
    assert r.status_code == 422


def test_mood_one_entry_per_day(registered):
    client, tokens = registered
    h = auth_header(tokens)
    assert client.put("/mental/moods", headers=h, json={"mood": 3}).status_code == 403
    _consent(client, tokens)
    client.put("/mental/moods", headers=h, json={"mood": 2, "note": "tired"})
    client.put("/mental/moods", headers=h, json={"mood": 4, "note": "better"})
    client.put("/mental/moods", headers=h, json={"mood": 5, "day": "2026-10-01"})
    moods = client.get("/mental/moods?days=365", headers=h).json()
    today = [m for m in moods if m["note"] == "better"]
    assert len(today) == 1 and today[0]["mood"] == 4
    assert all(m["note"] != "tired" for m in moods)
    assert client.put("/mental/moods", headers=h, json={"mood": 6}).status_code == 422


def test_breathing_sessions(registered):
    client, tokens = registered
    h = auth_header(tokens)
    client.post("/mental/breathing", headers=h, json={"pattern": "box", "duration_seconds": 120})
    client.post("/mental/breathing", headers=h, json={"pattern": "4-7-8", "duration_seconds": 60})
    assert client.get("/mental/breathing/summary", headers=h).json() == {"sessions": 2, "total_minutes": 3}
