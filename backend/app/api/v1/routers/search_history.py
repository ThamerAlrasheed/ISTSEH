from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.base import MessageResponse
from app.schemas.search import SearchHistoryCreateRequest
from app.services.auth import CurrentIdentity, get_current_identity
from app.services.search_history import add_search_history, list_search_history


router = APIRouter()


@router.get("")
async def get_search_history(
    limit: int = Query(default=10, ge=1, le=50),
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await list_search_history(session, identity, limit=limit)


@router.post("", response_model=MessageResponse)
async def create_search_history_route(
    payload: SearchHistoryCreateRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    await add_search_history(session, identity, payload)
    return MessageResponse(message="Search history recorded.")
