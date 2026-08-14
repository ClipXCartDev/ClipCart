# ClipCart — Decision Record

> Locked project decisions. This is the source of truth. Any change here requires client approval.
> Governing principle: **stable, secure, maintainable production app within a ₹1.8 lakh budget — not the most advanced system.** When two solutions work, pick the one with less code, maintenance, infra, config and deployment effort while staying secure and production-ready. If a single developer can't comfortably own it end-to-end, it's too complex.

## 1. Product
> Reconciled with client requirements doc "Content Marketplace Platform" + client answers (2026-08-10). See §11 for the full reconciliation.

| # | Decision |
|---|----------|
| 1.1 | ClipCart is a **subscription content-marketplace** for **short meme-type / funny reel clips** (often cut from movies) aimed at Instagram page owners. Customers subscribe, browse/search/favorite, customize admin-defined fields, and **export MP4 on their own device**. |
| 1.2 | **All video rendering happens on-device** (in the mobile app). The server never renders video. |
| 1.3 | **Three roles:** **Customer** (subscriber), **Editor** (trusted creator — uploads clips, admin-approved, earns payouts), **Admin** (owner — approvals, plans, pricing, payouts, analytics, settings). |
| 1.4 | **Editors cannot publish directly** — every upload enters an Admin review (approve / reject / request changes). Editors track their uploads, sales/downloads, earnings, and request payouts. |
| 1.5 | Backend scope: auth, RBAC (3 roles), subscription + multi-plan management, Binance Pay verification, clip/template management + **approval workflow**, metadata (movie/genre/language/etc.), favorites, download history, notifications, editor payouts, reports/analytics, admin ops. |

## 2. Market & Payments
| # | Decision |
|---|----------|
| 2.1 | **Global** audience, **English-only** at launch (i18n-ready structure, no other languages now). |
| 2.2 | **Crypto-only. Binance Pay Merchant API is the single payment method.** No Razorpay/Stripe/PayPal. No payment abstraction, no multi-gateway design. |
| 2.3 | **Purchase happens on the website only.** Mobile apps are **read-only** — they unlock access already paid for. No in-app purchase. |
| 2.4 | Flow: backend creates Binance Pay order → user pays in Binance Pay → Binance sends **signed webhook** → backend **verifies signature** → subscription activates automatically. **Frontend payment status is never trusted.** |
| 2.5 | Settlement in **USDT**, **BEP20** preferred network. App does not handle individual coins — Binance Pay does. |
| 2.6 | **Manual renewal only.** No auto-renew, no recurring billing. On expiry premium locks; renewing on web auto-restores access. |
| 2.7 | On success: **confirmation email** + **payment history** visible in account. Full payment audit logs stored. |

## 3. Platforms
| # | Decision |
|---|----------|
| 3.1 | **Flutter** for Android + iOS. **Flutter Web** (same codebase) for website + admin panel. One frontend codebase total. |
| 3.2 | **Website is NOT a video editor.** No editing, template customization, FFmpeg, `ffmpeg.wasm`, video rendering or MP4 export on web. All editing, preview rendering and MP4 export happen **only in the mobile apps**. Website = landing, pricing, auth, library, previews, template details, Binance Pay checkout, payment result, account dashboard, subscription status, payment history, device management, profile/settings. |

## 4. Backend & Infrastructure
| # | Decision |
|---|----------|
| 4.1 | **FastAPI** backend, **PostgreSQL** database. |
| 4.2 | **Single Ubuntu VPS.** Docker + Docker Compose. **Caddy** as reverse proxy + automatic HTTPS. |
| 4.3 | **Local VPS storage** for all assets. No object/cloud storage. |
| 4.4 | **Daily backup** is sufficient. No clustering, HA, distributed storage, or horizontal scaling. |
| 4.5 | **Forbidden infra:** Redis, object/cloud storage, Kubernetes, microservices, message queues, background workers. |
| 4.6 | **Email:** simplest free/low-cost SMTP (default candidate **Brevo** free tier). SMTP creds in env vars only. No email infra beyond that. |

## 5. Video Rendering
| # | Decision |
|---|----------|
| 5.1 | **FFmpeg (community fork) called directly** on-device. No abstraction/engine layer. |
| 5.2 | Server delivers template assets + editable-field metadata only. Device composites & encodes MP4. |

## 6. Security (practical, production-grade)
| # | Decision |
|---|----------|
| 6.1 | **Argon2** password hashing. **JWT** access token + **refresh token**. **HTTPS** everywhere (Caddy). |
| 6.2 | **Role-based access** (user / admin). **Rate limiting**. **Input validation**. **Parameterized queries** (no raw string SQL). |
| 6.3 | **Audit logs** for sensitive actions. **Private storage** — originals never public. **Temporary signed URLs** for premium assets. |
| 6.4 | Mobile: **encrypted local storage**, **secure token storage**, **Flutter obfuscation**, **SSL pinning**, **root / jailbreak / tamper detection**. |
| 6.5 | **No hardcoded secrets** — everything via environment variables. |
| 6.6 | Every premium request validates **Authentication + Subscription + Device Binding + Authorization**. |

## 7. Device Binding
| # | Decision |
|---|----------|
| 7.1 | Max **2 active devices** per account. 3rd login → show registered devices → remove one **or** buy an extra device slot. |
| 7.2 | Track per device: **Device ID, OS, App Version, Last Login, Last Active, IP Address, Country**. |
| 7.3 | **Admin can revoke** any device. |

## 8. Testing (approved stack only)
| # | Decision |
|---|----------|
| 8.1 | Backend/API: **Pytest + HTTPX**. Web + Admin: **Playwright**. Flutter: **integration_test**. |
| 8.2 | Manual: **Android emulator + real Android device + client iPhone** (acceptance). |
| 8.3 | Automate **only critical journeys**. **Forbidden:** Appium, Maestro, Mobilewright, BrowserStack, cloud device farms. |
| 8.4 | Deliverables per module: manual test cases, regression checklist, API test cases, security checklist, bug reports. |

## 9. Delivery Model
| # | Decision |
|---|----------|
| 9.1 | Features are built **end-to-end, one at a time**: **Design → Backend → Database → API → Flutter UI → Testing → QA → Client Review → Merge**. |
| 9.2 | Never leave half-completed modules. Working software after every milestone. |
| 9.3 | Git repo: `git@github.com:ClipXCartDev/ClipCart.git`. Commits authored as **Gulshan Tomar Dev** (no AI attribution). |

## 10. Documentation Set (lean)
`00-decisions` · `01-product` · `02-ux-flows` · `03-architecture` · `04-database` · `05-api` · `06-design-system` · `07-standards-delivery`. New docs added only if a real gap appears during the build.

## 11. Client-Doc Reconciliation (2026-08-10)
Reconciled with the client requirements doc ("Content Marketplace Platform") + client answers. These **update earlier decisions where noted**.

| # | Decision | Updates |
|---|----------|---------|
| 11.1 | **Product** = subscription marketplace for short **meme-type / funny reel clips** (movie-sourced). Confirmed the meme/fun visual direction is correct. | supersedes 1.1 "premium video templates" |
| 11.2 | **Three roles** (Customer / Editor / Admin) with **mandatory Admin approval** of every editor upload (approve / reject / request-changes). | supersedes earlier "2 DB roles" |
| 11.3 | **Multiple subscription plans**, admin-configurable (e.g. Free + Basic / Professional / Agency) — each with export limit, download quality, price, features. Upgrade = a new purchase (still crypto + manual renewal, no recurring/proration). | supersedes "single premium tier" |
| 11.4 | **Editor payouts** based on downloads/exports of their approved clips; editor can **request withdrawal**; **Admin approves** and marks paid (manual settlement — no automated crypto payout). Rate/basis = business decision (placeholder). | new |
| 11.5 | **Clip metadata + filters:** category, **movie name, genre, language**, tags, duration, resolution, upload date, popularity, # downloads. Filters incl. editor & premium. | extends template metadata |
| 11.6 | **Customer features to include:** favorites/saved, **download history**, invoices, rich search/filters, notifications. Home: featured + newest + trending + testimonials + pricing + CTA. Admin: create categories, **feature clips**, analytics (incl. MRR/top-editors). | new |
| 11.7 | **Customization fields (superset, admin picks per clip):** subtitle text/font/size/color/position/**stroke/background/username/CTA/ending-screen/aspect-ratio** + watermark/logo. | extends editable fields |
| 11.8 | **CONFIRMED FINAL (client):** the **website has NO edit and NO export** — it handles plans, pricing, subscribe, and account management only. **Customize + export happen exclusively in the mobile app** (on-device). This settles the earlier divergence — no server-side rendering. | reaffirms 3.2 · **resolved** |
| 11.9 | **Scale:** build **lean v1 on a single VPS** but keep DB/API schema clean so future scaling isn't blocked. "Thousands of users" treated as a **future phase**, not v1 infra. | reaffirms §4 |
| 11.10 | **Payment stays crypto-only Binance Pay** (client-approved) despite mainstream IG-creator audience — flagged as a conversion risk to revisit with client. | reaffirms 2.2 |
| 11.11 | **Dark theme** is a client design requirement — dark is first-class; default light/dark to be confirmed (doc leans dark). | design note |
| 11.12 | **Editor = layer-based overlay editor** on a **fixed base clip** (client-clarified 2026-08-10, WhatsApp). Customer adds/edits overlay **layers** — the doc's customization list (subtitle/logo/username/CTA/ending/watermark) **are the layers**. **Subtitles are a timed track**: multiple lines at different timestamps (start–end), styled per line. Live preview = time-synced overlay widgets; export = FFmpeg (`subtitles=ass` / `drawtext enable=between` + `overlay`). Detailed in `09-feature-logic §8–9`. | details doc customization |
| 11.13 | **Explicitly OUT of scope** (NOT a general video editor / not CapCut): trimming/splitting the base clip, multi-track audio editing, waveform edit, **AI clipper**, cover/thumbnail generation. Base clip is fixed (admin-provided). | scope guard |
| 11.14 | **Google Sign-In** added as an auth method (mobile + web) alongside email/password. Backend verifies the Google ID token, links by email or creates a `customer`. Editors work **in-app (Creator mode)** on mobile — no separate web login. | extends §6 auth |
| 11.15 | **UI design LOCKED (2026-08-14):** "Sunset Coral" system (accent gradient orange→pink `#ff8a3d`→`#ff4d6d`), same theme across mobile + web + admin, light+dark. UX = RenderForest-style clip **gallery** → tap → full-screen **swipe player** (Instagram) → **CapCut-style** layer editor. Product wording is **meme/movie "clips"** (not "reels"). Reference deck: 48 screens at `design-preview/v2.html` (live `…/v5.html`). Supersedes `06-design-system` visuals. | design lock |

**Open client items:** exact plan names/prices/limits; payout rate & basis; crypto-only conversion acceptance; default theme; confirm layer-editor scope (timed subtitles yes, full video-editing no). *(Web-vs-app export — RESOLVED, see 11.8.)*

---

## Implementation Risks (engineering-only)
| ID | Risk | Severity | Mitigation |
|----|------|----------|------------|
| R1 | Live Binance Pay merchant credentials pending; development must proceed without them. | 🟠 Medium | Build & test against Binance Pay sandbox/test credentials; switch to live via env vars at go-live. |
| R2 | FFmpeg community fork maintenance risk (official kit retired 2025). | 🟠 Medium | Pin a known-good fork version; direct usage keeps the swap cost low if ever needed. |
| R3 | On-device MP4 export performance/quality on low-end devices. | 🟠 Medium | Define a render/perf budget in `03-architecture`; validate on a real Android device + client iPhone. |
