begin;

alter table if exists public.users enable row level security;
alter table if exists public.appointments enable row level security;
alter table if exists public.search_history enable row level security;
alter table if exists public.medications enable row level security;
alter table if exists public.user_medications enable row level security;

alter table if exists public.user_medications
  add column if not exists dosage text,
  add column if not exists frequency_per_day integer not null default 1,
  add column if not exists frequency_hours integer,
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists notes text,
  add column if not exists is_active boolean not null default true;

drop policy if exists "users_select_own" on public.users;
drop policy if exists "users_insert_own" on public.users;
drop policy if exists "users_update_own" on public.users;

create policy "users_select_own"
  on public.users
  for select
  to authenticated
  using (id = auth.uid());

create policy "users_insert_own"
  on public.users
  for insert
  to authenticated
  with check (id = auth.uid());

create policy "users_update_own"
  on public.users
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "appointments_select_own" on public.appointments;
drop policy if exists "appointments_insert_own" on public.appointments;
drop policy if exists "appointments_update_own" on public.appointments;
drop policy if exists "appointments_delete_own" on public.appointments;

create policy "appointments_select_own"
  on public.appointments
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "appointments_insert_own"
  on public.appointments
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "appointments_update_own"
  on public.appointments
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "appointments_delete_own"
  on public.appointments
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "search_history_select_own" on public.search_history;
drop policy if exists "search_history_insert_own" on public.search_history;
drop policy if exists "search_history_delete_own" on public.search_history;

create policy "search_history_select_own"
  on public.search_history
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "search_history_insert_own"
  on public.search_history
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "search_history_delete_own"
  on public.search_history
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "user_medications_select_own" on public.user_medications;
drop policy if exists "user_medications_insert_own" on public.user_medications;
drop policy if exists "user_medications_update_own" on public.user_medications;
drop policy if exists "user_medications_delete_own" on public.user_medications;

create policy "user_medications_select_own"
  on public.user_medications
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "user_medications_insert_own"
  on public.user_medications
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "user_medications_update_own"
  on public.user_medications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "user_medications_delete_own"
  on public.user_medications
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "medications_select_public" on public.medications;
drop policy if exists "medications_insert_authenticated" on public.medications;

create policy "medications_select_public"
  on public.medications
  for select
  to anon, authenticated
  using (true);

create policy "medications_insert_authenticated"
  on public.medications
  for insert
  to authenticated
  with check (true);

commit;
