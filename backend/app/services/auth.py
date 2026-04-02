from __future__ import annotations

from dataclasses import dataclass
from datetime import timedelta
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.db import get_db_session
from app.core.security import (
    create_access_token,
    create_opaque_token,
    decode_access_token,
    hash_password,
    hash_token,
    utcnow,
    verify_password,
)
from app.models.device_session import DeviceSession
from app.models.password_reset_token import PasswordResetToken
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.repositories.user_repository import get_user_by_email, get_user_by_id
from app.schemas.auth import AuthSessionResponse, AuthUser


bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(slots=True)
class CurrentIdentity:
    user: User
    auth_mode: str
    device_session: DeviceSession | None = None


def to_auth_user(user: User) -> AuthUser:
    return AuthUser(
        id=str(user.id),
        email=user.email,
        role=user.role.value,
        first_name=user.first_name,
        last_name=user.last_name,
        phone_number=user.phone_number,
        date_of_birth=user.date_of_birth,
        allergies=user.allergies or [],
        conditions=user.conditions or [],
    )


async def register_user(
    session: AsyncSession,
    *,
    email: str,
    password: str,
    first_name: str,
    last_name: str,
    phone_number: str | None,
    date_of_birth,
    allergies: list[str],
    conditions: list[str],
) -> AuthSessionResponse:
    if await get_user_by_email(session, email):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email is already registered.")

    user = User(
        email=email.lower(),
        password_hash=hash_password(password),
        first_name=first_name.strip(),
        last_name=last_name.strip(),
        phone_number=(phone_number or "").strip() or None,
        date_of_birth=date_of_birth,
        allergies=_clean_text_list(allergies),
        conditions=_clean_text_list(conditions),
    )
    session.add(user)
    await session.flush()
    response = await issue_session_for_user(session, user)
    await session.commit()
    return response


async def login_user(session: AsyncSession, *, email: str, password: str) -> AuthSessionResponse:
    user = await get_user_by_email(session, email)
    if not user or not verify_password(password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password.")

    response = await issue_session_for_user(session, user)
    await session.commit()
    return response


async def refresh_user_session(session: AsyncSession, refresh_token: str) -> AuthSessionResponse:
    token_hash = hash_token(refresh_token)
    token_row = await _get_refresh_token(session, token_hash)
    if not token_row or token_row.revoked_at or token_row.expires_at <= utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Refresh token is invalid.")

    user = await get_user_by_id(session, token_row.user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User no longer exists.")

    token_row.revoked_at = utcnow()
    response = await issue_session_for_user(session, user, replaced_token=token_row)
    await session.commit()
    return response


async def logout_identity(
    session: AsyncSession,
    identity: CurrentIdentity,
    refresh_token: str | None = None,
) -> None:
    if identity.auth_mode == "device":
        if identity.device_session is None:
            return
        identity.device_session.revoked_at = utcnow()
        await session.commit()
        return

    if refresh_token:
        token_hash = hash_token(refresh_token)
        token_row = await _get_refresh_token(session, token_hash)
        if token_row and token_row.user_id == identity.user.id:
            token_row.revoked_at = utcnow()
    else:
        stmt = select(RefreshToken).where(
            RefreshToken.user_id == identity.user.id,
            RefreshToken.revoked_at.is_(None),
        )
        result = await session.execute(stmt)
        for row in result.scalars():
            row.revoked_at = utcnow()

    await session.commit()


async def create_password_reset_token(session: AsyncSession, email: str) -> str | None:
    user = await get_user_by_email(session, email)
    if not user:
        return None

    raw_token = create_opaque_token()
    reset_token = PasswordResetToken(
        user_id=user.id,
        token_hash=hash_token(raw_token),
        expires_at=utcnow() + timedelta(minutes=settings.password_reset_token_expire_minutes),
    )
    session.add(reset_token)
    await session.commit()
    return raw_token if settings.is_development else None


async def confirm_password_reset(session: AsyncSession, token: str, new_password: str) -> None:
    stmt = select(PasswordResetToken).where(
        PasswordResetToken.token_hash == hash_token(token),
        PasswordResetToken.used_at.is_(None),
    )
    row = (await session.execute(stmt)).scalar_one_or_none()
    if not row or row.expires_at <= utcnow():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Reset token is invalid.")

    user = await get_user_by_id(session, row.user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    user.password_hash = hash_password(new_password)
    row.used_at = utcnow()

    stmt = select(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
    result = await session.execute(stmt)
    for refresh_token in result.scalars():
        refresh_token.revoked_at = utcnow()

    await session.commit()


async def issue_session_for_user(
    session: AsyncSession,
    user: User,
    *,
    replaced_token: RefreshToken | None = None,
) -> AuthSessionResponse:
    raw_refresh_token = create_opaque_token()
    refresh_token = RefreshToken(
        user_id=user.id,
        token_hash=hash_token(raw_refresh_token),
        expires_at=utcnow() + timedelta(days=settings.refresh_token_expire_days),
        replaced_by_token_id=replaced_token.id if replaced_token else None,
    )
    session.add(refresh_token)
    await session.flush()

    access_token = create_access_token(str(user.id), user.role.value)
    return AuthSessionResponse(
        access_token=access_token,
        refresh_token=raw_refresh_token,
        expires_in=settings.access_token_expire_minutes * 60,
        user=to_auth_user(user),
    )


async def get_current_identity(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    x_device_token: str | None = Header(default=None, alias="X-Device-Token"),
    session: AsyncSession = Depends(get_db_session),
) -> CurrentIdentity:
    if credentials:
        payload = decode_access_token(credentials.credentials)
        user = await get_user_by_id(session, UUID(payload.sub))
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found.")
        return CurrentIdentity(user=user, auth_mode="jwt")

    if x_device_token:
        stmt: Select[tuple[DeviceSession]] = select(DeviceSession).where(
            DeviceSession.device_token == x_device_token,
            DeviceSession.revoked_at.is_(None),
        )
        device_session = (await session.execute(stmt)).scalar_one_or_none()
        if not device_session:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Device session is invalid.")
        user = await get_user_by_id(session, device_session.user_id)
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Patient no longer exists.")
        return CurrentIdentity(user=user, auth_mode="device", device_session=device_session)

    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required.")


async def require_jwt_identity(identity: CurrentIdentity = Depends(get_current_identity)) -> CurrentIdentity:
    if identity.auth_mode != "jwt":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="JWT authentication required.")
    return identity


async def _get_refresh_token(session: AsyncSession, token_hash: str) -> RefreshToken | None:
    stmt = select(RefreshToken).where(RefreshToken.token_hash == token_hash)
    return (await session.execute(stmt)).scalar_one_or_none()


def _clean_text_list(values: list[str]) -> list[str]:
    return [value.strip() for value in values if value and value.strip()]
