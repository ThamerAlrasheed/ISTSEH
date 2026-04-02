from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.schemas.base import APIModel


class AppointmentUpsertRequest(APIModel):
    title: str = Field(min_length=1)
    doctor_name: str | None = None
    appointment_time: datetime
    notes: str | None = None


class AppointmentResponse(APIModel):
    id: str
    user_id: str
    title: str
    doctor_name: str | None
    appointment_time: datetime
    notes: str | None
