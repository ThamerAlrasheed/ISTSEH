from __future__ import annotations

from datetime import datetime

from pydantic import Field

from app.schemas.base import APIModel


class SearchHistoryCreateRequest(APIModel):
    search_query: str = Field(min_length=1)


class SearchHistoryEntry(APIModel):
    id: str
    search_query: str
    created_at: datetime


class SearchHistoryListResponse(APIModel):
    recent: list[str]
    entries: list[SearchHistoryEntry]
