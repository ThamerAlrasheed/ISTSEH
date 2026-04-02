from __future__ import annotations

from datetime import date, time

from pydantic import Field

from app.schemas.base import APIModel


class CurrentUserResponse(APIModel):
    id: str
    email: str | None
    role: str
    auth_mode: str
    first_name: str | None
    last_name: str | None
    phone_number: str | None
    date_of_birth: date | None
    allergies: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)


class UpdateProfileRequest(APIModel):
    first_name: str | None = None
    last_name: str | None = None
    phone_number: str | None = None
    date_of_birth: date | None = None
    allergies: list[str] | None = None
    conditions: list[str] | None = None


class RoutineResponse(APIModel):
    breakfast_time: time | None
    lunch_time: time | None
    dinner_time: time | None
    bedtime: time | None
    wakeup_time: time | None


class UpdateRoutineRequest(APIModel):
    breakfast_time: time | None = None
    lunch_time: time | None = None
    dinner_time: time | None = None
    bedtime: time | None = None
    wakeup_time: time | None = None
