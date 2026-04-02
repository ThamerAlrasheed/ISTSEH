from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medication import Medication


async def get_medication_by_name(session: AsyncSession, name: str) -> Medication | None:
    stmt = select(Medication).where(func.lower(Medication.name) == name.strip().lower())
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def get_medication_by_id(session: AsyncSession, medication_id: UUID) -> Medication | None:
    return await session.get(Medication, medication_id)
