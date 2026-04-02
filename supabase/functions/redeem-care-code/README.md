This Edge Function redeems a 6-digit care code server-side.

It:
- validates that the code exists and is still active,
- creates the patient `device_sessions` row with service-role permissions,
- marks the code as `used`,
- returns the `patient_id` and `device_token` back to the app.

Required secret:
- `SUPABASE_SERVICE_ROLE_KEY`

Deploy:

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
supabase functions deploy redeem-care-code
```
