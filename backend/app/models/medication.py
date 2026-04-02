from __future__ import annotations

from sqlalchemy import Integer, Text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Medication(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "medications"

    name: Mapped[str] = mapped_column(Text, nullable=False)
    aliases: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    image_urls: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    how_to_use: Mapped[str | None] = mapped_column(Text, nullable=True)
    side_effects: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    contraindications: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    food_rule: Mapped[str] = mapped_column(Text, nullable=False, default="none")
    min_interval_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    active_ingredients: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
