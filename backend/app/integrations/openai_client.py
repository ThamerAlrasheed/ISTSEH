from __future__ import annotations

import json

from openai import AsyncOpenAI

from app.core.config import settings
from app.schemas.drug_intel import DrugIntelResponse


SYSTEM_PROMPT = """
You are a pharmacy assistant. Return ONLY strict JSON.
Keys:
- title: string
- strengths: array like ["5 mg", "10 mg"]
- food_rule: "before_food" | "after_food" | "none"
- min_interval_hours: integer hours or null
- interactions_to_avoid: array of short strings
- common_side_effects: array of short strings
- how_to_take: array of short bullets
- what_for: array of short bullets
Do not include any keys other than those above.
""".strip()


class OpenAIIntegration:
    def __init__(self) -> None:
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is not configured.")
        self._client = AsyncOpenAI(api_key=settings.openai_api_key)

    async def fetch_by_name(self, name: str) -> DrugIntelResponse:
        completion = await self._client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"Medication name: {name}\nReturn the JSON now."},
            ],
        )
        content = completion.choices[0].message.content or "{}"
        return DrugIntelResponse.model_validate(self._parse_json(content, fallback_title=name))

    async def fetch_by_image(self, image_url: str) -> DrugIntelResponse:
        completion = await self._client.chat.completions.create(
            model=settings.openai_model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "Identify the medication in this image and return the JSON now."},
                        {"type": "image_url", "image_url": {"url": image_url}},
                    ],
                },
            ],
        )
        content = completion.choices[0].message.content or "{}"
        return DrugIntelResponse.model_validate(self._parse_json(content, fallback_title="Medication"))

    def _parse_json(self, raw: str, fallback_title: str) -> dict:
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            start = raw.find("{")
            end = raw.rfind("}")
            if start < 0 or end <= start:
                raise RuntimeError("Model did not return valid JSON.")
            parsed = json.loads(raw[start : end + 1])

        parsed.setdefault("title", fallback_title)
        parsed.setdefault("strengths", [])
        parsed.setdefault("food_rule", "none")
        parsed.setdefault("min_interval_hours", None)
        parsed.setdefault("interactions_to_avoid", [])
        parsed.setdefault("common_side_effects", [])
        parsed.setdefault("how_to_take", [])
        parsed.setdefault("what_for", [])
        return parsed
