from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field, field_validator


class SolveFile(BaseModel):
    filename: str
    content_base64: str
    mime_type: str

    @field_validator("filename", "content_base64", "mime_type")
    @classmethod
    def not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Field cannot be empty")
        return value


class TripletexCredentials(BaseModel):
    base_url: str
    session_token: str

    @field_validator("base_url")
    @classmethod
    def url_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("base_url cannot be empty")
        return value

    @field_validator("session_token")
    @classmethod
    def token_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("session_token cannot be empty")
        return value


class SolveRequest(BaseModel):
    prompt: str
    files: list[SolveFile] = Field(default_factory=list)
    tripletex_credentials: TripletexCredentials

    @field_validator("prompt")
    @classmethod
    def prompt_not_empty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("prompt cannot be empty")
        return value


class SolveResponse(BaseModel):
    status: str = "completed"


class ParsedIntent(BaseModel):
    task_type: str
    action: str
    language: str | None = None
    entities: dict[str, Any] = Field(default_factory=dict)
    fields: dict[str, Any] = Field(default_factory=dict)
    confidence: float = 0.0


class ExecutionResult(BaseModel):
    success: bool
    workflow_name: str
    created_ids: dict[str, Any] = Field(default_factory=dict)
    notes: list[str] = Field(default_factory=list)
    verification: dict[str, Any] = Field(default_factory=dict)
