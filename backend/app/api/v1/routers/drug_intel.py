from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.drug_intel import DrugIntelRequest
from app.services.drug_intel import resolve_drug_intel


router = APIRouter()


@router.post("/drug-intel")
async def drug_intel(payload: DrugIntelRequest, session: AsyncSession = Depends(get_db_session)):
    return await resolve_drug_intel(session, payload)
