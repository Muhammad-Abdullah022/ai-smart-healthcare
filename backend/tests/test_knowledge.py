"""Disease knowledge base and report range checks (no AI needed)."""
from app.ai.diseases import DISEASES, find_relevant, reference_notes
from app.ai.lab_ranges import check_values, parse_range


def test_knowledge_base_has_40_plus_complete_diseases():
    assert len(DISEASES) >= 40
    assert len({d.name for d in DISEASES}) == len(DISEASES)
    for d in DISEASES:
        assert d.names and d.symptoms and d.red_flags and d.tests and d.specialist and d.self_care


def test_matching_in_english_and_roman_urdu():
    assert find_relevant("2 din se bukhar, jism dard aur aankhon ke peeche dard")[0].name == "Dengue fever"
    assert find_relevant("burning urine and frequent urination")[0].name.startswith("Urinary")
    assert find_relevant("aadhe sar ka dard aur roshni se takleef")[0].name == "Migraine"
    assert reference_notes("hello") == ""
    assert "Danger signs" in reference_notes("I think I have typhoid")


def test_parse_printed_ranges():
    assert parse_range("13.5 - 17.5") == (13.5, 17.5)
    assert parse_range("< 200") == (None, 200)
    assert parse_range("> 40") == (40, None)
    assert parse_range("0.7–1.3 mg/dL") == (0.7, 1.3)
    assert parse_range("") is None


def test_flags_are_computed_by_code_not_ai():
    values = [
        {"name": "Haemoglobin", "value": "10.1", "unit": "g/dL", "reference_range": "13.5-17.5", "flag": "normal"},
        {"name": "Serum Potassium", "value": "6.9", "unit": "mmol/L", "reference_range": "", "flag": "normal"},
        {"name": "HbA1c", "value": "5.2", "unit": "%", "reference_range": "", "flag": "high"},
        {"name": "Strange test", "value": "3", "unit": "x", "reference_range": "", "flag": "high"},
    ]
    hb, k, a1c, other = check_values(values, "male")
    assert (hb["flag"], hb["flag_source"]) == ("low", "report")
    assert (k["flag"], k["flag_source"], k["critical"]) == ("high", "standard", True)
    assert (a1c["flag"], a1c["flag_source"]) == ("normal", "standard")
    assert (other["flag"], other["flag_source"]) == ("high", "ai")
    female_hb = check_values([{"name": "Hb", "value": "12.5", "unit": "g/dL", "reference_range": ""}], "female")[0]
    assert female_hb["flag"] == "normal"
