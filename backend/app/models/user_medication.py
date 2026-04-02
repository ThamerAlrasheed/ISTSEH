from __future__ import annotations

from datetime import date
from uuid import UUID

from sqlalchemy import Boolean, Date, ForeignKey, Index, Integer, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class UserMedication(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "user_medications"
    __table_args__ = (
        Index("ix_user_medications_user_active", "user_id", "is_active"),
        Index("ix_user_medications_medication_id", "medication_id"),
    )

    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    medication_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("medications.id", ondelete="CASCADE"),
    )
    dosage: Mapped[str] = mapped_column(Text, nullable=False)
    frequency_per_day: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    frequency_hours: Mapped[int | None] = mapped_column(Integer, nullable=True)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
