from tests.conftest import VALID_USER, auth_header


def test_save_list_archive_private(registered):
    client, tokens = registered
    h = auth_header(tokens)
    r = client.post("/entries/39", headers=h, json={"data": {"condition": "Asthma", "since": "2015", "tags": ["lungs"]}})
    assert r.status_code == 201
    eid = r.json()["id"]
    assert client.get("/entries/39", headers=h).json()[0]["data"]["condition"] == "Asthma"
    other = client.post("/auth/register", json={**VALID_USER, "email": "b@example.com"}).json()
    assert client.get("/entries/39", headers=auth_header(other)).json() == []
    assert client.post(f"/entries/39/{eid}/archive", headers=auth_header(other)).status_code == 404
    assert client.post(f"/entries/39/{eid}/archive", headers=h).status_code == 204
    assert client.get("/entries/39", headers=h).json() == []


def test_entry_validation(registered):
    client, tokens = registered
    h = auth_header(tokens)
    assert client.post("/entries/51", headers=h, json={"data": {"a": "b"}}).status_code == 422
    assert client.post("/entries/5", headers=h, json={"data": {}}).status_code == 422
    assert client.post("/entries/5", headers=h, json={"data": {"Bad Key": "x"}}).status_code == 422
    assert client.post("/entries/5", headers=h, json={"data": {"note": "x" * 2001}}).status_code == 422
    assert client.post("/entries/5", headers=h, json={"data": {"nested": {"a": 1}}}).status_code == 422
    assert client.get("/entries/5").status_code == 401
