from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.appointment import Appointment
from app.schemas.appointment import AppointmentResponse, AppointmentUpsertRequest
from app.services.auth import CurrentIdentity


async def list_appointments(session: AsyncSession, identity: CurrentIdentity) -> list[AppointmentResponse]:
    stmt = (
        select(Appointment)
        .where(Appointment.user_id == identity.user.id)
        .order_by(Appointment.appointment_time.asc())
    )
    result = await session.execute(stmt)
    return [AppointmentResponse.model_validate(item) for item in result.scalars()]


async def create_appointment(
    session: AsyncSession,
    identity: CurrentIdentity,
    payload: AppointmentUpsertRequest,
) -> AppointmentResponse:
    appointment = Appointment(
        user_id=identity.user.id,
        title=payload.title.strip(),
        doctor_name=_optional_str(payload.doctor_name),
        appointment_time=payload.appointment_time,
        notes=_optional_str(payload.notes),
    )
    session.add(appointment)
    await session.commit()
    await session.refresh(appointment)
    return AppointmentResponse.model_validate(appointment)


async def update_appointment(
    session: AsyncSession,
    identity: CurrentIdentity,
    appointment_id: UUID,
    payload: AppointmentUpsertRequest,
) -> AppointmentResponse:
    appointment = await _get_owned_appointment(session, identity, appointment_id)
    appointment.title = payload.title.strip()
    appointment.doctor_name = _optional_str(payload.doctor_name)
    appointment.appointment_time = payload.appointment_time
    appointment.notes = _optional_str(payload.notes)
    await session.commit()
    await session.refresh(appointment)
    return AppointmentResponse.model_validate(appointment)


async def delete_appointment(session: AsyncSession, identity: CurrentIdentity, appointment_id: UUID) -> None:
    appointment = await _get_owned_appointment(session, identity, appointment_id)
    await session.delete(appointment)
    await session.commit()


async def _get_owned_appointment(
    session: AsyncSession,
    identity: CurrentIdentity,
    appointment_id: UUID,
) -> Appointment:
    stmt = select(Appointment).where(
        Appointment.id == appointment_id,
        Appointment.user_id == identity.user.id,
    )
    appointment = (await session.execute(stmt)).scalar_one_or_none()
    if not appointment:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Appointment not found.")
    return appointment


def _optional_str(value: str | None) -> str | None:
    if value is None:
        return None
    trimmed = value.strip()
    return trimmed or None
