from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.caregiver import RedeemCareCodeRequest
from app.services.caregiver import redeem_care_code


router = APIRouter()


@router.post("/redeem")
async def redeem(payload: RedeemCareCodeRequest, session: AsyncSession = Depends(get_db_session)):
    return await redeem_care_code(session, payload.code.strip())
