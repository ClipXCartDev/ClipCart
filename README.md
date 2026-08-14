# ClipCart

Subscription marketplace for short **meme / funny movie clips**. Customers browse, customize
(subtitles, logo, fonts) and **export MP4 on-device**; editors upload clips (admin-approved);
web handles plans, crypto checkout and account. Payments are **crypto-only via Binance Pay**.

> Governing principle: stable, secure, maintainable production app within a lean budget — see
> [`docs/00-decisions.md`](docs/00-decisions.md) (source of truth for all locked decisions).

## Monorepo layout
```
backend/          FastAPI + PostgreSQL API (auth, catalog, billing, admin)
docs/             Decision record, product, UX, design-system, feature logic
design-preview/   Design source (HTML prototype) — coral "Sunset" system, 48 screens
index.html …      Deployed design preview (GitHub Pages) for client review
docker-compose.yml, Caddyfile, .env.example
```

## Quick start (backend)
```bash
cd backend
python -m venv .venv && .venv\Scripts\activate      # Windows
pip install -r requirements.txt
uvicorn app.main:app --reload      # http://127.0.0.1:8000/docs
pytest                             # test suite
```
Full stack (Postgres + API + Caddy): `cp .env.example .env` then `docker compose up --build`.

## Design preview
Live: https://clipxcartdev.github.io/ClipCart/v5.html — Mobile (24) · Web (14) · Admin (10).

## Status
- ✅ **S0** Foundation · ✅ **S1** Auth & Identity (Argon2 · JWT · Google · device binding)
- 🔜 **S2** Catalog · **S3** Billing (Binance Pay) · **S4** Creator/payouts · **S5–7** Flutter app/web/admin

Authored by **Gulshan Tomar Dev**.
