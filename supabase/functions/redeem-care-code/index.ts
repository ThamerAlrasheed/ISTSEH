import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error(
    "Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY environment variables."
  );
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  let payload: { code?: string };
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: "Invalid request body." }, 400);
  }

  const code = (payload.code ?? "").trim();
  if (code.length !== 6 || !/^\d{6}$/.test(code)) {
    return jsonResponse({ error: "Enter a valid 6-digit code." }, 400);
  }

  const admin = createClient(supabaseUrl, supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: rows, error: codeLookupError } = await admin
    .from("care_codes")
    .select("id, patient_id, status, expires_at")
    .eq("code", code)
    .eq("status", "active")
    .limit(1);

  if (codeLookupError) {
    return jsonResponse({ error: codeLookupError.message }, 500);
  }

  const codeRow = rows?.[0];
  if (!codeRow) {
    return jsonResponse({ error: "Invalid code. Please check with your caregiver." }, 404);
  }

  const expiry = codeRow.expires_at ? new Date(codeRow.expires_at) : null;
  if (!expiry || Number.isNaN(expiry.getTime()) || expiry.getTime() <= Date.now()) {
    return jsonResponse({ error: "This code has expired. Ask your caregiver for a new one." }, 400);
  }

  const deviceToken = crypto.randomUUID();

  const { error: sessionError } = await admin.from("device_sessions").insert({
    user_id: codeRow.patient_id,
    device_token: deviceToken,
  });

  if (sessionError) {
    return jsonResponse({ error: sessionError.message }, 500);
  }

  const { error: updateError } = await admin
    .from("care_codes")
    .update({ status: "used" })
    .eq("id", codeRow.id)
    .eq("status", "active");

  if (updateError) {
    await admin.from("device_sessions").delete().eq("device_token", deviceToken);
    return jsonResponse({ error: updateError.message }, 500);
  }

  return jsonResponse(
    {
      patient_id: codeRow.patient_id,
      device_token: deviceToken,
    },
    200
  );
});

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
