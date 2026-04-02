from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.search_history import SearchHistory


async def list_search_entries_for_user(
    session: AsyncSession,
    user_id: UUID,
    limit: int = 10,
) -> list[SearchHistory]:
    stmt = (
        select(SearchHistory)
        .where(SearchHistory.user_id == user_id)
        .order_by(SearchHistory.created_at.desc())
        .limit(limit)
    )
    result = await session.execute(stmt)
    return result.scalars().all()
