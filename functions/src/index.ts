import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import cors from "cors";
import OpenAI from "openai";

admin.initializeApp();

// Secrets (v2): declare and bind at runtime
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

// CORS
const corsHandler = cors({ origin: true });

type DrugIntel = {
  title: string;
  strengths: string[];
  food_rule: "before_food" | "after_food" | "none";
  min_interval_hours: number | null;
  interactions_to_avoid: string[];
  common_side_effects: string[];
  how_to_take: string[];
  what_for: string[];
};

const systemPrompt = `
You are a pharmacy assistant. Return ONLY strict JSON (no prose) for the requested medication.
Keys:
- title: string
- strengths: array like ["5 mg","10 mg"]
- food_rule: "before_food" | "after_food" | "none"
- min_interval_hours: integer hours or null
- interactions_to_avoid: array of short strings
- common_side_effects: array of short strings
- how_to_take: array of short bullets
- what_for: array of short bullets
Do not include any keys other than those above.
`;

function safeParseJSON<T = unknown>(s: string): T {
  try { return JSON.parse(s) as T; }
  catch {
    const start = s.indexOf("{");
    const end = s.lastIndexOf("}");
    if (start >= 0 && end > start) return JSON.parse(s.slice(start, end + 1)) as T;
    throw new Error("Model did not return valid JSON.");
  }
}

export const drugIntel = onRequest(
  { region: "us-central1", cors: true, secrets: [OPENAI_API_KEY] },
  async (req, res) => {
    await new Promise<void>((resolve) => corsHandler(req, res, () => resolve()));

    if (req.method !== "POST") { res.status(405).send("Use POST"); return; }

    const name = (req.body?.name ?? "").toString().trim();
    if (!name) { res.status(400).json({ error: "Missing 'name'." }); return; }

    try {
      // ⬇️ Instantiate OpenAI **inside** the handler (secret available now)
      const openai = new OpenAI({ apiKey: OPENAI_API_KEY.value() });

      const chat = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: `Medication name: ${name}\nReturn the JSON now.` }
        ],
        // optional: enforce JSON if your SDK supports it
        // response_format: { type: "json_object" }
      });

      const raw = chat.choices?.[0]?.message?.content ?? "";
      const data = safeParseJSON<DrugIntel>(raw);

      const clean: DrugIntel = {
        title: (data.title || name).toString(),
        strengths: Array.isArray(data.strengths) ? data.strengths.map(String) : [],
        food_rule: (["before_food","after_food","none"] as const).includes(data.food_rule)
          ? data.food_rule : "none",
        min_interval_hours:
          Number.isFinite(data.min_interval_hours as any) ? Number(data.min_interval_hours) : null,
        interactions_to_avoid:
          Array.isArray(data.interactions_to_avoid) ? data.interactions_to_avoid.map(String) : [],
        common_side_effects:
          Array.isArray(data.common_side_effects) ? data.common_side_effects.map(String) : [],
        how_to_take: Array.isArray(data.how_to_take) ? data.how_to_take.map(String) : [],
        what_for: Array.isArray(data.what_for) ? data.what_for.map(String) : []
      };

      res.status(200).json(clean);
      return;
    } catch (e: any) {
      console.error(e);
      res.status(500).json({ error: e?.message ?? "Unknown error" });
      return;
    }
  }
);

