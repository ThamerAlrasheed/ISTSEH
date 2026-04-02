from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.appointment import Appointment


async def list_appointments_for_user(session: AsyncSession, user_id: UUID) -> list[Appointment]:
    stmt = select(Appointment).where(Appointment.user_id == user_id).order_by(Appointment.appointment_time.asc())
    result = await session.execute(stmt)
    return result.scalars().all()
