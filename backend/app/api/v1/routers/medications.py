from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.base import MessageResponse
from app.schemas.medication import ArchiveMedicationRequest, UserMedicationUpsertRequest
from app.services.auth import CurrentIdentity, get_current_identity
from app.services.medications import (
    archive_user_medication,
    create_user_medication,
    delete_user_medication,
    get_catalog_entry,
    list_user_medications,
    update_user_medication,
)


router = APIRouter()


@router.get("/user-medications")
async def get_user_medications(
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await list_user_medications(session, identity)


@router.post("/user-medications")
async def create_medication(
    payload: UserMedicationUpsertRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await create_user_medication(session, identity, payload)


@router.put("/user-medications/{medication_id}")
async def update_medication(
    medication_id: UUID,
    payload: UserMedicationUpsertRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await update_user_medication(session, identity, medication_id, payload)


@router.patch("/user-medications/{medication_id}/archive", response_model=MessageResponse)
async def archive_medication(
    medication_id: UUID,
    payload: ArchiveMedicationRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    await archive_user_medication(session, identity, medication_id, payload.archived)
    return MessageResponse(message="Medication updated.")


@router.delete("/user-medications/{medication_id}", response_model=MessageResponse)
async def delete_medication(
    medication_id: UUID,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    await delete_user_medication(session, identity, medication_id)
    return MessageResponse(message="Medication deleted.")


@router.get("/medications/catalog/{name}")
async def get_catalog(name: str, session: AsyncSession = Depends(get_db_session)):
    return await get_catalog_entry(session, name)
