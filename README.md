# MEDSAI (ISTSEH)

MEDSAI is a healthcare application with:

- a **FastAPI backend** in `backend/`
- a **SwiftUI iOS app** in `MEDSAI/`

This README is focused on getting you running quickly with a **local backend (no Docker for backend runtime)**.

## Project Structure

- `backend/` — FastAPI app, SQLAlchemy async models, Alembic migrations, tests
- `MEDSAI/` — iOS SwiftUI client
- `package.json` — root task runner for setup, dev, migrations, and tests

## Prerequisites

Install these before starting:

- **Node.js + npm** (for running root scripts)
- **Python 3.12+**
- **PostgreSQL 14+** (running locally)
- **Xcode 15+** (only if you want to run the iOS app)

Optional:

- **uv** (faster Python workflow): <https://docs.astral.sh/uv/>

## Quick Start (Local Backend, No Docker)

### 1) Install root tooling

From the repository root:

```bash
npm install
```

### 2) Create backend virtual environment + install dependencies

```bash
npm run setup
```

This script creates `backend/.venv` and installs backend + test dependencies.

### 3) Configure environment variables

The backend loads settings from `backend/.env`.

- `backend/.env` is already prepared with local defaults.
- If needed, regenerate from `backend/.env.example`.

Important values for local development:

- `DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/medsai`
- `JWT_SECRET_KEY=change-me` (change this for real environments)
- `OPENAI_API_KEY=` (optional unless using OpenAI-backed features)

### 4) Ensure local PostgreSQL is ready

Create the `medsai` database and ensure your credentials match `DATABASE_URL`.

Default expected local connection:

- host: `localhost`
- port: `5432`
- user: `postgres`
- password: `postgres`
- database: `medsai`

### 5) Run database migrations

```bash
npm run db:upgrade
```

### 6) Start the backend

```bash
npm run dev
```

Backend should now be available at:

- API docs: <http://127.0.0.1:8000/docs>
- Health check: <http://127.0.0.1:8000/health>

## NPM Scripts Reference

From repository root:

- `npm run setup` — install backend dependencies into `backend/.venv`
- `npm run dev` — run FastAPI locally with reload on `127.0.0.1:8000`
- `npm run db:upgrade` — apply Alembic migrations
- `npm run db:migrate` — generate an auto migration stub
- `npm run test` — run backend tests

### UV-based alternatives

- `npm run uv:setup`
- `npm run uv:db:upgrade`
- `npm run uv:dev`

## Run the iOS App

1. Open `MEDSAI.xcodeproj` in Xcode.
2. Confirm `BackendBaseURL` in `MEDSAI/Info.plist` points to your backend:
   - Simulator: `http://localhost:8000`
   - Physical device: use your Mac LAN IP (for example `http://192.168.1.10:8000`)
3. Build and run with `Cmd + R`.

The iOS app appends `/api/v1` automatically in `MEDSAI/Services/BackendClient.swift`.

## Testing

Run backend tests:

```bash
npm run test
```

## Troubleshooting

- **`connection refused` to Postgres**
  - confirm PostgreSQL is running locally on `localhost:5432`
  - verify username/password/database in `backend/.env`

- **Alembic migration fails**
  - re-check `DATABASE_URL`
  - ensure target database exists before running `npm run db:upgrade`

- **iOS app cannot reach backend**
  - simulator should use `http://localhost:8000`
  - physical device must use your Mac’s LAN IP and same Wi-Fi network

## Notes

- `docker-compose.yml` still exists for container workflows, but the local-first path above runs backend directly on your machine.
- Keep secrets out of git; `.env` files are already ignored.
