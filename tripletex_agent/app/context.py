import time
import uuid
from dataclasses import dataclass, field


@dataclass
class ExecutionContext:
    request_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    start_time: float = field(default_factory=time.perf_counter)
    api_call_count: int = 0
    error_4xx_count: int = 0
    workflow_name: str = ""
    detected_language: str = ""
    retry_used: bool = False
    verification_skipped: bool = False
    assume_fresh_account: bool = False
    invoice_order_flow_used: bool = False

    def elapsed_ms(self) -> int:
        return int((time.perf_counter() - self.start_time) * 1000)
