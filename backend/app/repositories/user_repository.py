from __future__ import annotations

from collections.abc import Sequence
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.caregiver_relation import CaregiverRelation
from app.models.user import User


async def get_user_by_id(session: AsyncSession, user_id: UUID) -> User | None:
    return await session.get(User, user_id)


async def get_user_by_email(session: AsyncSession, email: str) -> User | None:
    stmt = select(User).where(func.lower(User.email) == email.strip().lower())
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def list_patients_for_caregiver(session: AsyncSession, caregiver_id: UUID) -> Sequence[User]:
    stmt = (
        select(User)
        .join(CaregiverRelation, CaregiverRelation.patient_id == User.id)
        .where(CaregiverRelation.caregiver_id == caregiver_id)
        .order_by(User.created_at.asc())
    )
    result = await session.execute(stmt)
    return result.scalars().all()


async def count_patients_for_caregiver(session: AsyncSession, caregiver_id: UUID) -> int:
    stmt = select(func.count()).select_from(CaregiverRelation).where(
        CaregiverRelation.caregiver_id == caregiver_id
    )
    return int((await session.execute(stmt)).scalar_one())
