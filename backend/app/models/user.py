from __future__ import annotations

from datetime import date, time

from sqlalchemy import Date, Enum, Index, String, Text, Time, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import UserRole


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        Index(
            "ix_users_email_unique",
            "email",
            unique=True,
            postgresql_where=text("email IS NOT NULL"),
        ),
    )

    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, native_enum=False),
        nullable=False,
        default=UserRole.REGULAR,
    )
    first_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    last_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    phone_number: Mapped[str | None] = mapped_column(String(40), nullable=True)
    date_of_birth: Mapped[date | None] = mapped_column(Date, nullable=True)

    allergies: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)
    conditions: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, default=list)

    breakfast_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    lunch_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    dinner_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    bedtime: Mapped[time | None] = mapped_column(Time, nullable=True)
    wakeup_time: Mapped[time | None] = mapped_column(Time, nullable=True)

    refresh_tokens = relationship("RefreshToken", back_populates="user", cascade="all, delete-orphan")
    password_reset_tokens = relationship(
        "PasswordResetToken",
        back_populates="user",
        cascade="all, delete-orphan",
    )
    device_sessions = relationship("DeviceSession", back_populates="user", cascade="all, delete-orphan")
