from __future__ import annotations

from pydantic import Field, model_validator

from app.schemas.base import APIModel


class DrugIntelRequest(APIModel):
    name: str | None = None
    image_url: str | None = None

    @model_validator(mode="after")
    def validate_payload(self) -> "DrugIntelRequest":
        if not self.name and not self.image_url:
            raise ValueError("Either name or image_url is required.")
        return self


class DrugIntelResponse(APIModel):
    title: str
    strengths: list[str] = Field(default_factory=list)
    food_rule: str = "none"
    min_interval_hours: int | None = None
    interactions_to_avoid: list[str] = Field(default_factory=list)
    common_side_effects: list[str] = Field(default_factory=list)
    how_to_take: list[str] = Field(default_factory=list)
    what_for: list[str] = Field(default_factory=list)
