from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db_session
from app.schemas.auth import (
    LoginRequest,
    LogoutRequest,
    PasswordResetConfirmRequest,
    PasswordResetRequest,
    PasswordResetRequestResponse,
    RefreshRequest,
    RegisterRequest,
)
from app.schemas.base import MessageResponse
from app.services.auth import (
    confirm_password_reset,
    create_password_reset_token,
    get_current_identity,
    login_user,
    logout_identity,
    refresh_user_session,
    register_user,
)


router = APIRouter()


@router.post("/register")
async def register(payload: RegisterRequest, session: AsyncSession = Depends(get_db_session)):
    return await register_user(
        session,
        email=payload.email,
        password=payload.password,
        first_name=payload.first_name,
        last_name=payload.last_name,
        phone_number=payload.phone_number,
        date_of_birth=payload.date_of_birth,
        allergies=payload.allergies,
        conditions=payload.conditions,
    )


@router.post("/login")
async def login(payload: LoginRequest, session: AsyncSession = Depends(get_db_session)):
    return await login_user(session, email=payload.email, password=payload.password)


@router.post("/refresh")
async def refresh(payload: RefreshRequest, session: AsyncSession = Depends(get_db_session)):
    return await refresh_user_session(session, payload.refresh_token)


@router.post("/logout", response_model=MessageResponse)
async def logout(
    payload: LogoutRequest,
    identity=Depends(get_current_identity),
    session: AsyncSession = Depends(get_db_session),
):
    await logout_identity(session, identity, payload.refresh_token)
    return MessageResponse(message="Logged out.")


@router.post("/password-reset/request", response_model=PasswordResetRequestResponse)
async def request_password_reset(
    payload: PasswordResetRequest,
    session: AsyncSession = Depends(get_db_session),
):
    debug_token = await create_password_reset_token(session, payload.email)
    return PasswordResetRequestResponse(
        message="If that email exists, a reset token has been created.",
        debug_token=debug_token,
    )


@router.post("/password-reset/confirm", response_model=MessageResponse)
async def confirm_password_reset_route(
    payload: PasswordResetConfirmRequest,
    session: AsyncSession = Depends(get_db_session),
):
    await confirm_password_reset(session, payload.token, payload.new_password)
    return MessageResponse(message="Password has been reset.")
