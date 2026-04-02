from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.schemas.base import APIModel


class PatientSummary(APIModel):
    id: str
    first_name: str | None
    last_name: str | None


class CreateCaregiverPatientRequest(APIModel):
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    date_of_birth: date
    allergies: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)


class CreateCaregiverPatientResponse(APIModel):
    patient_id: str
    code: str
    expires_at: datetime


class RedeemCareCodeRequest(APIModel):
    code: str = Field(min_length=6, max_length=6)


class RedeemCareCodeResponse(APIModel):
    patient_id: str
    device_token: str
