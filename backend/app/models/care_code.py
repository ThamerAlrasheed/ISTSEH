from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, Enum, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import CareCodeStatus


class CareCode(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "care_codes"
    __table_args__ = (
        Index("ix_care_codes_code_unique", "code", unique=True),
        Index("ix_care_codes_patient_id", "patient_id"),
        Index("ix_care_codes_caregiver_id", "caregiver_id"),
    )

    code: Mapped[str] = mapped_column(String(6), nullable=False)
    patient_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    caregiver_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[CareCodeStatus] = mapped_column(
        Enum(CareCodeStatus, native_enum=False),
        nullable=False,
        default=CareCodeStatus.ACTIVE,
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
