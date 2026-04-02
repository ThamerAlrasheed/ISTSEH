from __future__ import annotations

from datetime import date

from pydantic import EmailStr, Field

from app.schemas.base import APIModel


class AuthUser(APIModel):
    id: str
    email: str | None
    role: str
    first_name: str | None
    last_name: str | None
    phone_number: str | None
    date_of_birth: date | None
    allergies: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)


class AuthSessionResponse(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: AuthUser


class RegisterRequest(APIModel):
    email: EmailStr
    password: str = Field(min_length=8)
    first_name: str = Field(min_length=1)
    last_name: str = Field(min_length=1)
    phone_number: str | None = None
    date_of_birth: date | None = None
    allergies: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)


class LoginRequest(APIModel):
    email: EmailStr
    password: str


class RefreshRequest(APIModel):
    refresh_token: str


class LogoutRequest(APIModel):
    refresh_token: str | None = None


class PasswordResetRequest(APIModel):
    email: EmailStr


class PasswordResetRequestResponse(APIModel):
    message: str
    debug_token: str | None = None


class PasswordResetConfirmRequest(APIModel):
    token: str
    new_password: str = Field(min_length=8)
