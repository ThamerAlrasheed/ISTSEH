from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medication import Medication
from app.models.user_medication import UserMedication
from app.repositories.medication_repository import get_medication_by_name
from app.schemas.drug_intel import DrugIntelResponse
from app.schemas.medication import MedicationCatalogEntry, UserMedicationResponse, UserMedicationUpsertRequest
from app.services.auth import CurrentIdentity


async def list_user_medications(session: AsyncSession, identity: CurrentIdentity) -> list[UserMedicationResponse]:
    stmt = (
        select(UserMedication, Medication)
        .join(Medication, Medication.id == UserMedication.medication_id)
        .where(UserMedication.user_id == identity.user.id, UserMedication.is_active.is_(True))
        .order_by(UserMedication.created_at.asc())
    )
    result = await session.execute(stmt)
    return [_to_user_medication_response(user_med, medication) for user_med, medication in result.all()]


async def create_user_medication(
    session: AsyncSession,
    identity: CurrentIdentity,
    payload: UserMedicationUpsertRequest,
) -> UserMedicationResponse:
    medication = await get_or_create_medication(
        session,
        name=payload.name,
        food_rule=payload.food_rule,
    )
    user_medication = UserMedication(
        user_id=identity.user.id,
        medication_id=medication.id,
        dosage=payload.dosage.strip(),
        frequency_per_day=payload.frequency_per_day,
        frequency_hours=payload.frequency_hours,
        start_date=payload.start_date,
        end_date=payload.end_date,
        notes=_normalize_notes(payload.notes),
        is_active=True,
    )
    session.add(user_medication)
    await session.commit()
    await session.refresh(user_medication)
    return _to_user_medication_response(user_medication, medication)


async def update_user_medication(
    session: AsyncSession,
    identity: CurrentIdentity,
    medication_id: UUID,
    payload: UserMedicationUpsertRequest,
) -> UserMedicationResponse:
    user_medication = await _get_owned_user_medication(session, identity, medication_id)
    medication = await get_or_create_medication(session, name=payload.name, food_rule=payload.food_rule)

    user_medication.medication_id = medication.id
    user_medication.dosage = payload.dosage.strip()
    user_medication.frequency_per_day = payload.frequency_per_day
    user_medication.frequency_hours = payload.frequency_hours
    user_medication.start_date = payload.start_date
    user_medication.end_date = payload.end_date
    user_medication.notes = _normalize_notes(payload.notes)
    user_medication.is_active = True

    await session.commit()
    await session.refresh(user_medication)
    return _to_user_medication_response(user_medication, medication)


async def archive_user_medication(
    session: AsyncSession,
    identity: CurrentIdentity,
    medication_id: UUID,
    archived: bool,
) -> None:
    user_medication = await _get_owned_user_medication(session, identity, medication_id)
    user_medication.is_active = not archived
    await session.commit()


async def delete_user_medication(
    session: AsyncSession,
    identity: CurrentIdentity,
    medication_id: UUID,
) -> None:
    user_medication = await _get_owned_user_medication(session, identity, medication_id)
    await session.delete(user_medication)
    await session.commit()


async def get_catalog_entry(session: AsyncSession, name: str) -> MedicationCatalogEntry:
    medication = await get_medication_by_name(session, name)
    if not medication:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Medication not found in catalog.")
    return MedicationCatalogEntry.model_validate(medication)


async def upsert_catalog_from_drug_intel(
    session: AsyncSession,
    payload: DrugIntelResponse,
    searched_name: str,
) -> Medication:
    medication = await get_or_create_medication(
        session,
        name=payload.title or searched_name,
        food_rule=payload.food_rule,
        details=payload,
        searched_name=searched_name,
    )
    await session.commit()
    return medication


async def get_or_create_medication(
    session: AsyncSession,
    *,
    name: str,
    food_rule: str = "none",
    details: DrugIntelResponse | None = None,
    searched_name: str | None = None,
) -> Medication:
    medication = await get_medication_by_name(session, name)
    if medication is None and searched_name and searched_name.lower() != name.lower():
        medication = await get_medication_by_name(session, searched_name)

    if medication is None:
        medication = Medication(
            name=name.strip(),
            food_rule=food_rule or "none",
            aliases=[],
            image_urls=[],
            side_effects=[],
            contraindications=[],
            active_ingredients=[],
        )
        session.add(medication)
        await session.flush()

    if searched_name and searched_name.strip() and searched_name.strip().lower() != medication.name.lower():
        alias = searched_name.strip()
        if alias not in medication.aliases:
            medication.aliases = [*medication.aliases, alias]

    if details is not None:
        medication.food_rule = details.food_rule or medication.food_rule or "none"
        medication.min_interval_hours = details.min_interval_hours
        medication.how_to_use = "\n".join([item.strip() for item in details.how_to_take if item.strip()]) or medication.how_to_use
        medication.side_effects = _merge_lists(medication.side_effects, details.common_side_effects)
        medication.contraindications = _merge_lists(medication.contraindications, details.interactions_to_avoid)

    return medication


async def _get_owned_user_medication(
    session: AsyncSession,
    identity: CurrentIdentity,
    medication_id: UUID,
) -> UserMedication:
    stmt = select(UserMedication).where(
        UserMedication.id == medication_id,
        UserMedication.user_id == identity.user.id,
    )
    user_medication = (await session.execute(stmt)).scalar_one_or_none()
    if not user_medication:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Medication not found.")
    return user_medication


def _to_user_medication_response(user_medication: UserMedication, medication: Medication) -> UserMedicationResponse:
    return UserMedicationResponse(
        id=str(user_medication.id),
        user_id=str(user_medication.user_id),
        medication_id=str(user_medication.medication_id),
        name=medication.name,
        dosage=user_medication.dosage,
        frequency_per_day=user_medication.frequency_per_day,
        frequency_hours=user_medication.frequency_hours,
        start_date=user_medication.start_date,
        end_date=user_medication.end_date,
        notes=user_medication.notes,
        is_active=user_medication.is_active,
        food_rule=medication.food_rule,
        min_interval_hours=medication.min_interval_hours,
        active_ingredients=medication.active_ingredients,
    )


def _normalize_notes(notes: str | None) -> str | None:
    if not notes:
        return None
    trimmed = notes.strip()
    return trimmed or None


def _merge_lists(left: list[str], right: list[str]) -> list[str]:
    values: list[str] = []
    seen: set[str] = set()
    for raw in [*left, *right]:
        value = raw.strip()
        if value and value.lower() not in seen:
            values.append(value)
            seen.add(value.lower())
    return values
