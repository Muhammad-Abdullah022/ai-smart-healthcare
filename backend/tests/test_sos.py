from tests.conftest import auth_header


def test_sos_returns_numbers_contacts_and_message(registered):
    client, tokens = registered
    h = auth_header(tokens)
    client.patch("/profile", headers=h, json={
        "blood_group": "O+", "allergies": ["Penicillin"],
        "emergency_contacts": [{"name": "Ali", "phone": "03001234567", "relation": "Brother"}]})
    r = client.post("/sos", headers=h, json={"note": "Fell down stairs"})
    assert r.status_code == 201
    body = r.json()
    assert body["emergency_numbers"][0]["number"] == "1122"
    assert body["contacts"][0]["phone"] == "03001234567"
    assert "Ayesha Khan needs help" in body["message"] and "O+" in body["message"] and "Penicillin" in body["message"]
    assert body["sms_sent"] is False and body["location_included"] is False


def test_location_only_with_consent(registered):
    client, tokens = registered
    h = auth_header(tokens)
    loc = {"latitude": 31.5204, "longitude": 74.3587}
    assert client.post("/sos", headers=h, json=loc).json()["location_included"] is False
    client.post("/consents", headers=h, json={"category": "location", "granted": True})
    body = client.post("/sos", headers=h, json=loc).json()
    assert body["location_included"] is True
    assert "maps.google.com/?q=31.52040,74.35870" in body["message"]
    history = client.get("/sos", headers=h).json()
    assert len(history) == 2 and history[0]["location_included"] is True


def test_sos_requires_login_and_valid_coordinates(client, registered):
    client2, tokens = registered
    assert client.post("/sos", json={}).status_code == 401
    assert client2.post("/sos", headers=auth_header(tokens), json={"latitude": 200, "longitude": 0}).status_code == 422
