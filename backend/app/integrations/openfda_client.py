from __future__ import annotations

from typing import Any

import httpx

from app.core.config import settings
from app.schemas.drug_intel import DrugIntelResponse


class OpenFDAIntegration:
    async def fetch_by_name(self, name: str) -> DrugIntelResponse:
        query = f'openfda.brand_name:"{name}" OR openfda.generic_name:"{name}"'
        url = f"{settings.openfda_base_url}/drug/label.json"

        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.get(url, params={"search": query, "limit": 1})
            response.raise_for_status()
            payload = response.json()

        results = payload.get("results") or []
        if not results:
            return DrugIntelResponse(title=name)

        result = results[0]
        return DrugIntelResponse(
            title=self._first_string(result.get("openfda", {}).get("brand_name")) or name,
            strengths=self._string_list(result.get("dosage_and_administration")),
            food_rule="none",
            min_interval_hours=None,
            interactions_to_avoid=self._string_list(
                result.get("drug_interactions") or result.get("contraindications")
            ),
            common_side_effects=self._string_list(result.get("adverse_reactions")),
            how_to_take=self._string_list(result.get("dosage_and_administration")),
            what_for=self._string_list(result.get("indications_and_usage")),
        )

    @staticmethod
    def _string_list(value: Any) -> list[str]:
        if not value:
            return []
        if isinstance(value, list):
            return [str(item).strip() for item in value if str(item).strip()]
        return [str(value).strip()]

    @staticmethod
    def _first_string(value: Any) -> str | None:
        values = OpenFDAIntegration._string_list(value)
        return values[0] if values else None
