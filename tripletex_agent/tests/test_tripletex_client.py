from unittest.mock import Mock

import pytest
import requests

from app.tripletex_client import TripletexClient, TripletexValidationError


def make_response(status_code=200, json_data=None, text=""):
    response = Mock(spec=requests.Response)
    response.status_code = status_code
    response.ok = 200 <= status_code < 300
    response.text = text
    response.content = b'{}' if json_data is not None else b""
    response.json.return_value = json_data
    return response


def test_handle_value_response():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    response = make_response(json_data={"value": {"id": 1, "name": "Test"}})
    data = client._handle_response(response)
    assert data["id"] == 1


def test_list_values_response():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    client.get = Mock(return_value={"values": [{"id": 1}, {"id": 2}]})
    values = client.list_values("/customer")
    assert len(values) == 2


def test_validation_error():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    response = make_response(status_code=400, json_data={"message": "bad request"}, text="bad request")
    with pytest.raises(TripletexValidationError):
        client._handle_response(response)


def test_build_url():
    client = TripletexClient(base_url="https://example.com/v2", session_token="token")
    assert "employee" in client._build_url("/employee")
