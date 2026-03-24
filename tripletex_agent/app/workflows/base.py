from __future__ import annotations

from abc import ABC, abstractmethod

from app.schemas import ExecutionResult, ParsedIntent
from app.tripletex_client import TripletexClient


class BaseWorkflow(ABC):
    name = "base"

    @abstractmethod
    def validate_intent(self, intent: ParsedIntent) -> None:
        raise NotImplementedError

    @abstractmethod
    def execute(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        context: dict,
    ) -> ExecutionResult:
        raise NotImplementedError

    @abstractmethod
    def verify(
        self,
        intent: ParsedIntent,
        client: TripletexClient,
        execution_result: ExecutionResult,
    ) -> dict:
        raise NotImplementedError
