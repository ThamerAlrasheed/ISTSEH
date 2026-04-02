from __future__ import annotations

import asyncio
from collections.abc import Sequence

import asyncpg
from sqlalchemy.dialects.postgresql import insert

from app.core.config import settings
from app.core.db import AsyncSessionLocal
from app.models import (
    Appointment,
    CareCode,
    CaregiverRelation,
    DeviceSession,
    Medication,
    SearchHistory,
    User,
    UserMedication,
)


TABLE_IMPORT_ORDER = [
    "users",
    "medications",
    "user_medications",
    "appointments",
    "search_history",
    "caregiver_relations",
    "care_codes",
    "device_sessions",
]


async def main() -> None:
    if not settings.source_database_url:
        raise RuntimeError("SOURCE_DATABASE_URL is required to run the import.")

    source = await asyncpg.connect(settings.source_database_url)
    try:
        async with AsyncSessionLocal() as session:
            await import_users(source, session)
            await import_table(source, session, "public.medications", Medication, ["id"])
            await import_table(source, session, "public.user_medications", UserMedication, ["id"])
            await import_table(source, session, "public.appointments", Appointment, ["id"])
            await import_table(source, session, "public.search_history", SearchHistory, ["id"])
            await import_table(source, session, "public.caregiver_relations", CaregiverRelation, ["caregiver_id", "patient_id"])
            await import_table(source, session, "public.care_codes", CareCode, ["id"])
            await import_table(source, session, "public.device_sessions", DeviceSession, ["id"])
            await session.commit()
    finally:
        await source.close()


async def import_users(source: asyncpg.Connection, session) -> None:
    rows = await source.fetch("select * from public.users")
    auth_rows = await source.fetch("select id, email, encrypted_password from auth.users")
    auth_by_id = {row["id"]: row for row in auth_rows}

    payloads = []
    for row in rows:
        auth_row = auth_by_id.get(row["id"])
        payload = dict(row)
        payload["email"] = auth_row["email"] if auth_row else payload.get("email")
        payload["password_hash"] = auth_row["encrypted_password"] if auth_row else payload.get("password_hash")
        payloads.append(payload)

    await upsert_rows(session, User.__table__, payloads, ["id"])


async def import_table(source: asyncpg.Connection, session, source_table: str, model, key_columns: Sequence[str]) -> None:
    rows = await source.fetch(f"select * from {source_table}")
    payloads = [dict(row) for row in rows]
    if not payloads:
        return
    await upsert_rows(session, model.__table__, payloads, key_columns)


async def upsert_rows(session, table, rows: list[dict], key_columns: Sequence[str]) -> None:
    if not rows:
        return

    valid_columns = {column.name for column in table.columns}
    filtered_rows = [{key: value for key, value in row.items() if key in valid_columns} for row in rows]
    stmt = insert(table).values(filtered_rows)
    update_values = {
        column.name: getattr(stmt.excluded, column.name)
        for column in table.columns
        if column.name not in key_columns
    }
    stmt = stmt.on_conflict_do_update(index_elements=list(key_columns), set_=update_values)
    await session.execute(stmt)


if __name__ == "__main__":
    asyncio.run(main())
