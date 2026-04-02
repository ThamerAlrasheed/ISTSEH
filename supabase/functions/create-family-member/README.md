# create-family-member

Supabase Edge Function used by the iOS family flow.

What it does:
- verifies the signed-in caregiver from the incoming Supabase auth token,
- enforces the current `2 family members max` rule,
- creates the patient row in `users`,
- creates the caregiver link in `caregiver_relations`,
- creates the 6-digit care code in `care_codes`,
- returns the generated code to the app.

Required secrets:
- `SUPABASE_SERVICE_ROLE_KEY`

Built-in Supabase Edge env vars used:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Deploy example:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
supabase functions deploy create-family-member
```

Local serve example:

```bash
supabase functions serve create-family-member --env-file supabase/.env.local
```

Expected response:

```json
{
  "patient_id": "uuid",
  "code": "123456",
  "expires_at": "2026-03-29T10:00:00.000Z"
}
```
