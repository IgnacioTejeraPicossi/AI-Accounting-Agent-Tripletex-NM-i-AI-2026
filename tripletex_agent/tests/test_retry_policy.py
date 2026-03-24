from app.retry_policy import normalize_payload_for_retry, should_retry_validation_error


def test_should_retry_validation_error():
    assert should_retry_validation_error("Validation error: unknown field", {"a": 1}) is True
    assert should_retry_validation_error("Server exploded", {"a": 1}) is False


def test_should_not_retry_without_payload():
    assert should_retry_validation_error("Validation error", None) is False


def test_remove_empty_fields():
    payload = {"name": "Test", "email": "", "phone": None}
    normalized = normalize_payload_for_retry("/employee", payload)
    assert normalized["name"] == "Test"
    assert "email" not in normalized
    assert "phone" not in normalized


def test_employee_phone_normalization():
    payload = {"firstName": "Ola", "lastName": "Nordmann", "phone": "+47 12345678"}
    normalized = normalize_payload_for_retry("/employee", payload)
    assert "phone" not in normalized
    assert normalized["mobileNumber"] == "+47 12345678"


def test_invoice_numeric_normalization():
    payload = {
        "customer": {"id": 1},
        "orderLines": [{"count": "2", "unitPrice": "1500"}],
    }
    normalized = normalize_payload_for_retry("/invoice", payload)
    assert normalized["orderLines"][0]["count"] == 2
    assert normalized["orderLines"][0]["unitPrice"] == 1500.0
