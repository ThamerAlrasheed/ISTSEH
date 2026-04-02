from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.integrations.openai_client import OpenAIIntegration
from app.integrations.openfda_client import OpenFDAIntegration
from app.schemas.drug_intel import DrugIntelRequest, DrugIntelResponse
from app.services.medications import upsert_catalog_from_drug_intel


async def resolve_drug_intel(session: AsyncSession, payload: DrugIntelRequest) -> DrugIntelResponse:
    result: DrugIntelResponse | None = None
    openai_error: Exception | None = None

    if settings.openai_api_key:
        integration = OpenAIIntegration()
        try:
            if payload.image_url:
                result = await integration.fetch_by_image(payload.image_url)
            else:
                result = await integration.fetch_by_name(payload.name or "")
        except Exception as exc:  # noqa: BLE001
            openai_error = exc

    if result is None and payload.name:
        try:
            result = await OpenFDAIntegration().fetch_by_name(payload.name)
        except Exception as exc:  # noqa: BLE001
            if openai_error:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Drug lookup failed: {openai_error}; fallback failed: {exc}",
                ) from exc
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=f"Drug lookup failed: {exc}") from exc

    if result is None:
        if openai_error:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=f"Drug lookup failed: {openai_error}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="image_url lookup requires OPENAI_API_KEY to be configured.",
        )

    await upsert_catalog_from_drug_intel(session, result, payload.name or result.title)
    return result
