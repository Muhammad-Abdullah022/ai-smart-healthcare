from app.labs.catalog import family_of
from tests.conftest import auth_header


def test_family_matching():
    assert family_of("Complete Blood Count (CBC)") == "cbc"
    assert family_of("CBC") == "cbc"
    assert family_of("Dengue NS1 antigen") == "dengue"
    assert family_of("DENGUE SEROLOGY (IGM, IGG)") == "dengue"
    assert family_of("HBA1C") == "hba1c"
    assert family_of("HB") == "hb"
    assert family_of("PROTEIN/CREATININE RATIO") is None
    assert family_of("Urine Complete") == "urine"
    assert family_of("Something unknown") is None


def test_lab_options_lahore_uses_sourced_prices(registered):
    client, tokens = registered
    h = auth_header(tokens)
    r = client.get("/labs/options", headers=h, params={"city": "lahore", "tests": ["Thyroid function test (TSH)"]})
    data = r.json()
    t = data["tests"][0]
    assert t["name_en"].startswith("Thyroid")
    assert t["offers"], "Lahore has published TSH prices in the sourced data"
    prices = [o["price_pkr"] for o in t["offers"]]
    assert prices == sorted(prices)
    assert all(o["source_url"].startswith("https://") and o["checked"] for o in t["offers"])
    assert "confirm" in data["note"]


def test_lab_options_unknown_city_has_no_invented_labs(registered):
    client, tokens = registered
    data = client.get("/labs/options", headers=auth_header(tokens),
                      params={"city": "Atlantis", "tests": ["CBC"]}).json()
    assert data["known_city"] is False
    assert data["tests"][0]["offers"] == [] and data["labs_without_prices"] == []


def test_cities_list(registered):
    client, tokens = registered
    cities = client.get("/labs/cities", headers=auth_header(tokens)).json()
    assert len(cities) > 100 and cities[0]["labs"] >= cities[-1]["labs"]


def test_profile_city(registered):
    client, tokens = registered
    h = auth_header(tokens)
    assert client.patch("/profile", headers=h, json={"city": "Lahore"}).json()["city"] == "Lahore"


def test_chain_prices_apply_to_city_branches(registered):
    client, tokens = registered
    data = client.get("/labs/options", headers=auth_header(tokens),
                      params={"city": "Multan", "tests": ["Complete Blood Count (CBC)", "Dengue NS1"]}).json()
    cbc = data["tests"][0]
    labs = [o["lab"] for o in cbc["offers"]]
    assert "Chughtai Lab" in labs and "Excel Labs" in labs
    chughtai = next(o for o in cbc["offers"] if o["lab"] == "Chughtai Lab")
    assert chughtai["price_pkr"] == 800 and "branches in Multan" in chughtai["branch"]
    assert [o["price_pkr"] for o in cbc["offers"]] == sorted(o["price_pkr"] for o in cbc["offers"])


def test_government_rates_burewala(registered):
    client, tokens = registered
    data = client.get("/labs/options", headers=auth_header(tokens),
                      params={"city": "Burewala", "tests": ["Urine complete examination", "Blood sugar"]}).json()
    assert data["tests"][0]["offers"][0]["price_pkr"] == 10
    assert data["tests"][1]["offers"][0]["lab"] == "THQ Hospital Burewala Laboratory"


def test_phc_registered_labs_loaded(registered):
    client, tokens = registered
    h = auth_header(tokens)
    data = client.get("/labs/options", headers=h, params={"city": "Lahore", "other_limit": 2000}).json()
    assert data["other_total"] > 300 and len(data["labs_without_prices"]) == data["other_total"]
    taxila = client.get("/labs/options", headers=h, params={"city": "Taxila"}).json()
    assert taxila["other_total"] >= 5
