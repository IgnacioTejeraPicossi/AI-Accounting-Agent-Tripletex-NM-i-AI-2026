from unittest.mock import patch

from app.schemas import ExecutionResult
from app.task_router import UnsupportedTaskError


def test_solve_success(client, employee_payload):
    with patch("app.main.solve_task") as mock_solve:
        mock_solve.return_value = ExecutionResult(
            success=True,
            workflow_name="create_employee",
            created_ids={"employee_id": 123},
            notes=[],
            verification={"verified": True},
        )

        response = client.post("/solve", json=employee_payload)
        assert response.status_code == 200
        assert response.json() == {"status": "completed"}


def test_solve_unsupported_task(client, employee_payload):
    with patch("app.main.solve_task") as mock_solve:
        mock_solve.side_effect = UnsupportedTaskError("Unsupported task type: unsupported")

        response = client.post("/solve", json=employee_payload)
        assert response.status_code == 200
        assert response.json()["status"] == "completed"


def test_solve_empty_prompt(client):
    payload = {
        "prompt": "",
        "files": [],
        "tripletex_credentials": {
            "base_url": "https://example.com/v2",
            "session_token": "dummy-token",
        },
    }
    response = client.post("/solve", json=payload)
    assert response.status_code == 422
