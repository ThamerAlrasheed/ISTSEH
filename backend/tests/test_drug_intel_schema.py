from app.schemas.drug_intel import DrugIntelRequest


def test_drug_intel_request_accepts_name() -> None:
    payload = DrugIntelRequest(name="Panadol")
    assert payload.name == "Panadol"


def test_drug_intel_request_requires_name_or_image() -> None:
    try:
        DrugIntelRequest()
    except ValueError:
        pass
    else:
        raise AssertionError("Expected validation error for empty drug-intel request.")
