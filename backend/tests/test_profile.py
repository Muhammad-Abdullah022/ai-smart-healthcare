from tests.conftest import VALID_USER, auth_header


def test_new_profile_has_defaults(registered):
    client, tokens = registered
    response = client.get("/profile", headers=auth_header(tokens))
    assert response.status_code == 200
    body = response.json()
    assert body["full_name"] == "Ayesha Khan"
    assert body["blood_group"] == "Unknown"
    assert body["allergies"] == []


def test_update_profile(registered):
    client, tokens = registered
    response = client.patch(
        "/profile",
        headers=auth_header(tokens),
        json={
            "full_name": "Ayesha K.",
            "date_of_birth": "1999-05-14",
            "blood_group": "B+",
            "allergies": ["Penicillin"],
            "emergency_contacts": [{"name": "Ali", "phone": "03001234567", "relation": "Brother"}],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["full_name"] == "Ayesha K."
    assert body["date_of_birth"] == "1999-05-14"
    assert body["allergies"] == ["Penicillin"]
    # Reading again returns the saved data.
    again = client.get("/profile", headers=auth_header(tokens)).json()
    assert again["blood_group"] == "B+"


def test_invalid_blood_group_rejected(registered):
    client, tokens = registered
    response = client.patch("/profile", headers=auth_header(tokens), json={"blood_group": "Z+"})
    assert response.status_code == 422


def test_profile_requires_login(client):
    assert client.get("/profile").status_code == 401


def test_users_only_see_their_own_profile(registered):
    client, tokens_a = registered
    other = {**VALID_USER, "email": "bilal@example.com", "full_name": "Bilal"}
    tokens_b = client.post("/auth/register", json=other).json()
    client.patch("/profile", headers=auth_header(tokens_a), json={"allergies": ["Peanuts"]})
    profile_b = client.get("/profile", headers=auth_header(tokens_b)).json()
    assert profile_b["full_name"] == "Bilal"
    assert profile_b["allergies"] == []


def test_activity_shows_only_own_events(registered):
    client, tokens = registered
    client.patch("/profile", headers=auth_header(tokens), json={"blood_group": "A+"})
    actions = [a["action"] for a in client.get("/profile/activity", headers=auth_header(tokens)).json()]
    assert actions[0] == "profile.update" and "user.register" in actions
    other = client.post("/auth/register", json={**VALID_USER, "email": "z@example.com"}).json()
    assert [a["action"] for a in client.get("/profile/activity", headers=auth_header(other)).json()] == ["user.register"]
