from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.appointment import AppointmentUpsertRequest
from app.schemas.base import MessageResponse
from app.services.appointments import create_appointment, delete_appointment, list_appointments, update_appointment
from app.services.auth import CurrentIdentity, get_current_identity


router = APIRouter()


@router.get("")
async def get_appointments(
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await list_appointments(session, identity)


@router.post("")
async def create_appointment_route(
    payload: AppointmentUpsertRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await create_appointment(session, identity, payload)


@router.put("/{appointment_id}")
async def update_appointment_route(
    appointment_id: UUID,
    payload: AppointmentUpsertRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    return await update_appointment(session, identity, appointment_id, payload)


@router.delete("/{appointment_id}", response_model=MessageResponse)
async def delete_appointment_route(
    appointment_id: UUID,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    await delete_appointment(session, identity, appointment_id)
    return MessageResponse(message="Appointment deleted.")
