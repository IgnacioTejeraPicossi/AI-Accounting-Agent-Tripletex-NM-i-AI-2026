import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def employee_payload():
    return {
        "prompt": "Create an employee named Ola Nordmann with email ola.nordmann@example.com and phone +47 12345678",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def customer_payload():
    return {
        "prompt": "Create a customer named Nordic Bakery AS with email post@nordicbakery.no",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def product_payload():
    return {
        "prompt": "Create a product called Consulting Hour",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def project_payload():
    return {
        "prompt": "Create a project named Migration Project for customer Nordic Bakery AS",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }


@pytest.fixture
def invoice_payload():
    return {
        "prompt": "Create an invoice for customer Nordic Bakery AS with one line for Consulting Hour, quantity 2, unit price 1500",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }
