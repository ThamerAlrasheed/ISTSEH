from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.user import CurrentUserResponse, RoutineResponse, UpdateProfileRequest, UpdateRoutineRequest
from app.services.auth import CurrentIdentity, get_current_identity


router = APIRouter()


@router.get("", response_model=CurrentUserResponse)
async def get_me(identity: CurrentIdentity = Depends(get_current_identity)):
    user = identity.user
    return CurrentUserResponse(
        id=str(user.id),
        email=user.email,
        role=user.role.value,
        auth_mode=identity.auth_mode,
        first_name=user.first_name,
        last_name=user.last_name,
        phone_number=user.phone_number,
        date_of_birth=user.date_of_birth,
        allergies=user.allergies or [],
        conditions=user.conditions or [],
    )


@router.patch("/profile", response_model=CurrentUserResponse)
async def update_profile(
    payload: UpdateProfileRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    user = identity.user
    if payload.first_name is not None:
        user.first_name = payload.first_name.strip() or None
    if payload.last_name is not None:
        user.last_name = payload.last_name.strip() or None
    if payload.phone_number is not None:
        user.phone_number = payload.phone_number.strip() or None
    if payload.date_of_birth is not None:
        user.date_of_birth = payload.date_of_birth
    if payload.allergies is not None:
        user.allergies = [item.strip() for item in payload.allergies if item.strip()]
    if payload.conditions is not None:
        user.conditions = [item.strip() for item in payload.conditions if item.strip()]

    await session.commit()
    await session.refresh(user)
    return await get_me(identity)


@router.get("/routine", response_model=RoutineResponse)
async def get_routine(identity: CurrentIdentity = Depends(get_current_identity)):
    user = identity.user
    return RoutineResponse(
        breakfast_time=user.breakfast_time,
        lunch_time=user.lunch_time,
        dinner_time=user.dinner_time,
        bedtime=user.bedtime,
        wakeup_time=user.wakeup_time,
    )


@router.patch("/routine", response_model=RoutineResponse)
async def update_routine(
    payload: UpdateRoutineRequest,
    identity: CurrentIdentity = Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    user = identity.user
    if payload.breakfast_time is not None:
        user.breakfast_time = payload.breakfast_time
    if payload.lunch_time is not None:
        user.lunch_time = payload.lunch_time
    if payload.dinner_time is not None:
        user.dinner_time = payload.dinner_time
    if payload.bedtime is not None:
        user.bedtime = payload.bedtime
    if payload.wakeup_time is not None:
        user.wakeup_time = payload.wakeup_time

    await session.commit()
    await session.refresh(user)
    return await get_routine(identity)
