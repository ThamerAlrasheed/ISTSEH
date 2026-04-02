import { createClient } from "npm:@supabase/supabase-js@2";

type CreateFamilyMemberRequest = {
  first_name?: string;
  last_name?: string;
  date_of_birth?: string;
  allergies?: unknown;
  conditions?: unknown;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
  throw new Error(
    "Missing SUPABASE_URL, SUPABASE_ANON_KEY, or SUPABASE_SERVICE_ROLE_KEY environment variables."
  );
}

const admin = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function normalizeName(value: string | undefined) {
  return (value ?? "").trim();
}

function sanitizeStringArray(value: unknown) {
  if (!Array.isArray(value)) return [] as string[];

  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((item) => item.length > 0);
}

function randomCode() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { error: "Use POST for create-family-member." });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { error: "Missing Authorization header." });
  }

  const caller = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) {
    return json(401, { error: "Invalid caregiver session." });
  }

  let payload: CreateFamilyMemberRequest;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body." });
  }

  const firstName = normalizeName(payload.first_name);
  const lastName = normalizeName(payload.last_name);
  const dateOfBirth = (payload.date_of_birth ?? "").trim();
  const allergies = sanitizeStringArray(payload.allergies);
  const conditions = sanitizeStringArray(payload.conditions);

  if (!firstName || !lastName || !dateOfBirth) {
    return json(400, { error: "First name, last name, and date of birth are required." });
  }

  const caregiverId = authData.user.id;

  const { count, error: countError } = await admin
    .from("caregiver_relations")
    .select("patient_id", { count: "exact", head: true })
    .eq("caregiver_id", caregiverId);

  if (countError) {
    return json(500, { error: `Failed to validate caregiver capacity: ${countError.message}` });
  }

  if ((count ?? 0) >= 2) {
    return json(409, { error: "A caregiver can manage up to 2 family members in this version." });
  }

  const patientId = crypto.randomUUID();
  const code = randomCode();
  const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();

  const { error: patientError } = await admin.from("users").insert({
    id: patientId,
    role: "patient",
    first_name: firstName,
    last_name: lastName,
    date_of_birth: dateOfBirth,
    allergies,
    conditions,
  });

  if (patientError) {
    return json(500, { error: `Failed to create patient profile: ${patientError.message}` });
  }

  const { error: relationError } = await admin.from("caregiver_relations").insert({
    caregiver_id: caregiverId,
    patient_id: patientId,
  });

  if (relationError) {
    await admin.from("users").delete().eq("id", patientId);
    return json(500, { error: `Failed to create caregiver link: ${relationError.message}` });
  }

  const { error: codeError } = await admin.from("care_codes").insert({
    code,
    patient_id: patientId,
    caregiver_id: caregiverId,
    status: "active",
    expires_at: expiresAt,
  });

  if (codeError) {
    await admin.from("caregiver_relations").delete().eq("patient_id", patientId);
    await admin.from("users").delete().eq("id", patientId);
    return json(500, { error: `Failed to create care code: ${codeError.message}` });
  }

  await admin.from("users").update({ role: "caregiver" }).eq("id", caregiverId);

  return json(200, {
    patient_id: patientId,
    code,
    expires_at: expiresAt,
  });
});
