from __future__ import annotations

from datetime import date, datetime

from pydantic import Field

from app.schemas.base import APIModel


class MedicationCatalogEntry(APIModel):
    id: str
    name: str
    aliases: list[str] = Field(default_factory=list)
    image_urls: list[str] = Field(default_factory=list)
    how_to_use: str | None
    side_effects: list[str] = Field(default_factory=list)
    contraindications: list[str] = Field(default_factory=list)
    food_rule: str
    min_interval_hours: int | None
    active_ingredients: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class UserMedicationUpsertRequest(APIModel):
    name: str = Field(min_length=1)
    dosage: str = Field(min_length=1)
    frequency_per_day: int = Field(ge=1, le=12)
    frequency_hours: int | None = Field(default=None, ge=1, le=48)
    start_date: date
    end_date: date
    notes: str | None = None
    food_rule: str = "none"


class ArchiveMedicationRequest(APIModel):
    archived: bool


class UserMedicationResponse(APIModel):
    id: str
    user_id: str
    medication_id: str
    name: str
    dosage: str
    frequency_per_day: int
    frequency_hours: int | None
    start_date: date
    end_date: date
    notes: str | None
    is_active: bool
    food_rule: str
    min_interval_hours: int | None
    active_ingredients: list[str] = Field(default_factory=list)
