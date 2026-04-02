from __future__ import annotations

from datetime import timedelta
import random
from uuid import uuid4

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import create_opaque_token, utcnow
from app.models.care_code import CareCode
from app.models.caregiver_relation import CaregiverRelation
from app.models.device_session import DeviceSession
from app.models.enums import CareCodeStatus, UserRole
from app.models.user import User
from app.repositories.user_repository import count_patients_for_caregiver, list_patients_for_caregiver
from app.schemas.caregiver import CreateCaregiverPatientResponse, PatientSummary, RedeemCareCodeResponse
from app.services.auth import CurrentIdentity


async def list_caregiver_patients(session: AsyncSession, identity: CurrentIdentity) -> list[PatientSummary]:
    patients = await list_patients_for_caregiver(session, identity.user.id)
    return [
        PatientSummary(id=str(patient.id), first_name=patient.first_name, last_name=patient.last_name)
        for patient in patients
    ]


async def create_patient_for_caregiver(
    session: AsyncSession,
    identity: CurrentIdentity,
    *,
    first_name: str,
    last_name: str,
    date_of_birth,
    allergies: list[str],
    conditions: list[str],
) -> CreateCaregiverPatientResponse:
    current_count = await count_patients_for_caregiver(session, identity.user.id)
    if current_count >= 2:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A caregiver can manage up to 2 family members in this version.",
        )

    patient = User(
        id=uuid4(),
        role=UserRole.PATIENT,
        first_name=first_name.strip(),
        last_name=last_name.strip(),
        date_of_birth=date_of_birth,
        allergies=[item.strip() for item in allergies if item.strip()],
        conditions=[item.strip() for item in conditions if item.strip()],
    )
    session.add(patient)
    await session.flush()

    relation = CaregiverRelation(caregiver_id=identity.user.id, patient_id=patient.id)
    session.add(relation)

    code = await _generate_unique_code(session)
    expires_at = utcnow() + timedelta(hours=settings.care_code_expire_hours)
    care_code = CareCode(
        code=code,
        patient_id=patient.id,
        caregiver_id=identity.user.id,
        status=CareCodeStatus.ACTIVE,
        expires_at=expires_at,
    )
    session.add(care_code)

    if identity.user.role == UserRole.REGULAR:
        identity.user.role = UserRole.CAREGIVER

    await session.commit()

    return CreateCaregiverPatientResponse(
        patient_id=str(patient.id),
        code=code,
        expires_at=expires_at,
    )


async def redeem_care_code(session: AsyncSession, code: str) -> RedeemCareCodeResponse:
    stmt = select(CareCode).where(CareCode.code == code, CareCode.status == CareCodeStatus.ACTIVE)
    code_row = (await session.execute(stmt)).scalar_one_or_none()
    if not code_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid code. Please check with your caregiver.",
        )

    if code_row.expires_at <= utcnow():
        code_row.status = CareCodeStatus.EXPIRED
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This code has expired. Ask your caregiver for a new one.",
        )

    device_token = create_opaque_token()
    device_session = DeviceSession(user_id=code_row.patient_id, device_token=device_token)
    session.add(device_session)
    code_row.status = CareCodeStatus.USED
    await session.commit()

    return RedeemCareCodeResponse(patient_id=str(code_row.patient_id), device_token=device_token)


async def _generate_unique_code(session: AsyncSession) -> str:
    for _ in range(10):
        code = f"{random.randint(100000, 999999)}"
        stmt = select(CareCode.id).where(CareCode.code == code)
        if (await session.execute(stmt)).scalar_one_or_none() is None:
            return code
    raise HTTPException(status_code=500, detail="Failed to generate a unique care code.")
