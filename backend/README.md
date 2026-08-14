# ClipCart — Backend (FastAPI)

Sprint S0–S1: foundation + Auth & Identity.

## Stack
FastAPI · SQLAlchemy 2.0 · PostgreSQL (sqlite for local/tests) · Argon2 · JWT · Google Sign-In.

## Run locally (no Docker)
```bash
cd backend
python -m venv .venv && . .venv/Scripts/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload
# -> http://127.0.0.1:8000/health , docs at /docs
```
Defaults to a local `clipcart.db` sqlite file.

## Run the full stack (Docker)
```bash
cp .env.example .env   # from repo root; set JWT_SECRET
docker compose up --build
# API via Caddy at http://localhost/api/v1/...
```

## Tests
```bash
cd backend && pytest
```

## Auth endpoints (`/api/v1/auth`)
| Method | Path | Purpose |
|---|---|---|
| POST | `/register` | Create customer + issue tokens (+ bind device) |
| POST | `/login` | Email/password login (+ device binding, max 2) |
| POST | `/google` | Google Sign-In (verify ID token, link/create) |
| POST | `/refresh` | Rotate refresh → new access+refresh |
| GET | `/me` | Current user (Bearer access token) |
| GET | `/devices` | List bound devices |
| DELETE | `/devices/{id}` | Remove a device slot |

Device binding enforces `MAX_DEVICES` (default 2). A 3rd device returns `409` with the
current device list so the client can prompt "remove one or buy a slot".
