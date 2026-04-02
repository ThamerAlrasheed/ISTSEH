# MEDSAI Backend

FastAPI monorepo backend replacing Supabase and Firebase backend duties for the MEDSAI iOS app.

## Local development

1. Copy `.env.example` to `.env`.
2. Start Postgres and the API:

```bash
docker compose up --build
```

3. Run Alembic migrations:

```bash
cd backend
uv run alembic upgrade head
```

4. Run the app locally:

```bash
cd backend
uv run uvicorn app.main:app --reload
```

## Tests

```bash
cd backend
uv run pytest
```
