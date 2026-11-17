import json

from app.ai.service import AIService
from tests.conftest import auth_header
from tests.test_ai import FakeProvider


def test_search_brand_and_salt(registered):
    client, tokens = registered
    h = auth_header(tokens)
    r = client.get("/drugs/search", headers=h, params={"q": "napro"}).json()["results"]
    assert r[0]["brand"] == "Naprosyn" or any(x["brand"] == "Naprox" for x in r)
    by_salt = client.get("/drugs/search", headers=h, params={"q": "paracetamol"}).json()["results"]
    assert {"Panadol", "Calpol"} <= {x["brand"] for x in by_salt}
    assert client.get("/drugs/stats", headers=h).json()["brands"] >= 300


def test_same_salt_alternatives(registered):
    client, tokens = registered
    d = client.get("/drugs/detail", headers=auth_header(tokens), params={"name": "Naprox"}).json()
    assert d["generic"]["generic"] == "Naproxen" and not d["ai_guess"]
    alts = {a["brand"] for a in d["alternatives"]}
    assert "Naprosyn" in alts and "Naprox" not in alts and "Synflex" not in alts  # naproxen sodium is a different salt
    assert "pharmacist" in d["note"]


def test_unknown_brand_ai_guess(registered):
    client, tokens = registered
    client.app.state.ai = AIService([FakeProvider("gemini", [json.dumps(
        {"found": True, "brand": "Rarebrand", "generic": "Esomeprazole", "drug_class": "PPI", "uses": "acidity"})])],
        retry_delay=0)
    d = client.get("/drugs/detail", headers=auth_header(tokens), params={"name": "Rarebrand"}).json()
    assert d["ai_guess"] and "Nexum" in {a["brand"] for a in d["alternatives"]}


def test_pharmacies_every_city(registered):
    client, tokens = registered
    h = auth_header(tokens)
    p = client.get("/pharmacies", headers=h, params={"city": "Sahiwal"}).json()["pharmacies"]
    assert p[0]["name"] == "Allied Plus Pharmacy" and not p[0]["demo"]
    assert any(x["kind"] == "government" for x in p) and any(x["demo"] for x in p)
    small = client.get("/pharmacies", headers=h, params={"city": "Attock"}).json()["pharmacies"]
    assert len(small) >= 3
    assert all(x["open_24h"] for x in client.get("/pharmacies", headers=h,
                                                 params={"city": "Lahore", "open_24h": True}).json()["pharmacies"])
