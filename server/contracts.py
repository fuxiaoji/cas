"""Small shared HTTP and JSON contracts for the local CAS service."""
import json
from typing import Any

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field


def encode(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def deny(message: str, status: int = 400):
    raise HTTPException(status_code=status, detail=message)


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Mutation(StrictModel):
    request_id: str = Field(min_length=8, max_length=120, pattern=r"^[A-Za-z0-9_.:-]+$")
