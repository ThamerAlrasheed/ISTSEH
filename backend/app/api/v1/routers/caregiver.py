from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.caregiver import CreateCaregiverPatientRequest
from app.services.auth import CurrentIdentity, require_jwt_identity
from app.services.caregiver import create_patient_for_caregiver, list_caregiver_patients


router = APIRouter(prefix="/patients")


@router.get("")
async def list_patients(
    identity: CurrentIdentity = Depends(require_jwt_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await list_caregiver_patients(session, identity)


@router.post("")
async def create_patient(
    payload: CreateCaregiverPatientRequest,
    identity: CurrentIdentity = Depends(require_jwt_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await create_patient_for_caregiver(
        session,
        identity,
        first_name=payload.first_name,
        last_name=payload.last_name,
        date_of_birth=payload.date_of_birth,
        allergies=payload.allergies,
        conditions=payload.conditions,
    )
