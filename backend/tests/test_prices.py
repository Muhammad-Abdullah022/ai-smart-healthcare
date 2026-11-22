import json

from app.ai.service import AIService
from app.medicine_prices import pack_units, parse
from tests.conftest import auth_header
from tests.test_ai import FakeProvider

# Real rows from the DRAP 2021 MRP list (Open Data Pakistan), including its broken characters.
SAMPLE = '''_id,reg_no,Company Name,Brand Name,Formulation,Pack Size,MRP
313,101141,GlaxoSmithKline Consumer Healthcare Pakistan Limited,Panadol Extra Tablet,Paracetamol 500mg & Caffeine 65mg,100's,Rs. 182.47
314,101138,GlaxoSmithKline Consumer Healthcare Pakistan Limited,Panadol Tablet,Paracetamol 500mg,200's,Rs. 312.55
199,97715,Iqra Pharmaceuticals,Q-Mol 10mg/ml Intravenous Infusion,Each 100ml Infusion bottle contains: Paracetamolâ€¦1000mg,100ml,Rs. 98.44
237,827,Sanofi-aventis Pakistan limited,Flagyl Tablet,Metronidazole â€¦.400mg,20x10,Rs. 444.86
1,55113,AGP Limited,ABNIL Capsule 120MG,Orlistat,30's,"Rs. 1,644.15"
68,22244,GlaxoSmithKline Pakistan Ltd.,Augmentin Tablet 1g,Amoxycillin 875mg; Clavulanic Acid 125mg,6's,""
'''


def test_parse_fixes_text_and_units():
    rows = {r["brand"]: r for r in parse(SAMPLE)}
    assert rows["Flagyl Tablet"]["formulation"] == "Metronidazole 400mg"
    assert rows["Flagyl Tablet"]["units"] == 200 and rows["Flagyl Tablet"]["per_unit"] == 2.22
    assert rows["ABNIL Capsule 120MG"]["mrp"] == 1644.15
    assert rows["Augmentin Tablet 1g"]["mrp"] is None  # no price in the list -> none shown
    assert rows["Q-Mol 10mg/ml Intravenous Infusion"]["units"] is None
    assert pack_units("2x10's") == 20 and pack_units("120ml") is None


def test_price_comparison(registered):
    client, tokens = registered
    db = client.app.state.db

    async def put():
        await db.medicine_prices.insert_many(parse(SAMPLE))
    client.portal.call(put)
    r = client.get("/drugs/prices", headers=auth_header(tokens),
                   params={"name": "Panadol", "strength": "500", "city": "Sahiwal"}).json()
    assert r["generic"] == "Paracetamol" and r["price_list_loaded"]
    first = r["items"][0]
    assert first["brand"] == "Panadol Tablet" and first["same_strength"] and not first["combo"]
    assert any(i["combo"] for i in r["items"])  # Panadol Extra is listed after, marked as a mix
    assert r["cheapest"]["brand"] == "Panadol Tablet"
    assert "Calpol" in {b["brand"] for b in r["other_brands"]}
    assert r["pharmacies"] and "DRAP" in r["note"]


def test_identify_photo(registered):
    client, tokens = registered
    client.app.state.ai = AIService([FakeProvider("gemini", [json.dumps(
        {"found": True, "brand": "Panadol", "generic": "Paracetamol", "strength": "500 mg", "form": "tablet"})])],
        retry_delay=0)
    r = client.post("/drugs/identify", headers=auth_header(tokens),
                    files={"file": ("box.jpg", b"\xff\xd8fakejpeg", "image/jpeg")})
    assert r.status_code == 200, r.text
    assert r.json()["search"] == "Panadol" and r.json()["in_list"]
