from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.search_history import SearchHistory
from app.schemas.search import SearchHistoryCreateRequest, SearchHistoryEntry, SearchHistoryListResponse
from app.services.auth import CurrentIdentity


async def list_search_history(
    session: AsyncSession,
    identity: CurrentIdentity,
    limit: int = 10,
) -> SearchHistoryListResponse:
    from app.repositories.search_repository import list_search_entries_for_user

    rows = await list_search_entries_for_user(session, identity.user.id, limit=limit)

    recent: list[str] = []
    seen: set[str] = set()
    entries: list[SearchHistoryEntry] = []
    for row in rows:
        entries.append(SearchHistoryEntry.model_validate(row))
        key = row.search_query.strip().lower()
        if key and key not in seen:
            recent.append(row.search_query)
            seen.add(key)

    return SearchHistoryListResponse(recent=recent, entries=entries)


async def add_search_history(
    session: AsyncSession,
    identity: CurrentIdentity,
    payload: SearchHistoryCreateRequest,
) -> None:
    query = payload.search_query.strip()
    if not query:
        return
    row = SearchHistory(user_id=identity.user.id, search_query=query)
    session.add(row)
    await session.commit()
