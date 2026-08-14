# ClipCart — Product & Requirements

> Phase 1 deliverable. Defines *what* Version 1 is. Architecture, data, API and UI come in later docs.
> Business decisions (pricing, limits, durations) are marked **Pending Client Confirmation** — not assumed. Scope = exactly what the client approved, no additions, no reductions.

---

## 1. Project Overview

ClipCart is a subscription SaaS that sells access to **premium video templates**. A subscribed user picks a template, edits the fields the admin made editable, previews it, and **exports a finished MP4 rendered entirely on their own device**.

Subscriptions are **time-boxed** and paid in **crypto via Binance Pay on the website**. The mobile apps (Android/iOS) are consumption clients: browse, edit and export — but not buy.

**Why this shape:** on-device rendering removes all server video-processing cost, so the whole platform runs on a single VPS. The backend only moves small assets and metadata and checks entitlements.

### What ClipCart is NOT (scope guard)
- Not a video hosting/streaming platform.
- Not a social network (no feeds, follows, comments).
- Not a server-side video renderer.
- Not a user marketplace (admin publishes templates only).
- Not a multi-payment store (Binance Pay only).

---

## 2. User Roles

| Role | Description | Access |
|------|-------------|--------|
| **Guest** | Unauthenticated web visitor. | Marketing pages, pricing, register/login, low-res previews. |
| **Free User** | Registered, no active subscription. | Account, browse library, low-res previews. Cannot edit/export premium. |
| **Subscriber** | Registered with an active subscription. | Full library, edit editable fields, export MP4, up to 2 devices. |
| **Admin** | Staff, web admin panel only. | Manage templates, editable fields, subscriptions, users, devices, reports, audit logs. |

> Implemented as **2 DB roles** (`user` / `admin`). "Free vs Subscriber" is derived from subscription status, not stored separately — less code, fewer states.

---

## 3. Functional Requirements

*Clear, implementation-oriented requirements — grouped by module.*

### Authentication & Account
- **FR-1** Register with email + password (Argon2), requiring **email verification** before first login.
- **FR-2** Login issues a **JWT access token + refresh token**; logout revokes the refresh token on that device.
- **FR-3** Forgot/reset password via an emailed token link.
- **FR-4** View and update profile; change password.

### Subscription & Payment (web only)
- **FR-5** View available plans/pricing.
- **FR-6** Start checkout: backend creates a **Binance Pay order**; user pays inside Binance Pay.
- **FR-7** Backend verifies the **Binance Pay signed webhook** (processed idempotently) and **activates the subscription automatically**. Frontend payment status is never trusted.
- **FR-8** A subscription carries plan, start date, expiry date, export limit, device limit and status. On expiry premium locks automatically; **manual renewal** restores access after a verified payment.
- **FR-9** Send a **payment confirmation email**; show **payment history** in the account.

### Template Library
- **FR-10** Browse templates (thumbnail + preview video); **search/filter** by admin-defined categories/tags.
- **FR-11** Template detail view. Original assets are gated to subscribers; guests/free users see low-res/watermarked previews.

### Editing & Export (on-device)
- **FR-12** Open a template in the editor and edit **all editable fields the admin enabled** (see §6).
- **FR-13** Show a **live on-device preview** of edits.
- **FR-14** **Export MP4 on-device via FFmpeg**, enforcing the subscription's **export limit** and re-validating **auth + subscription + device + authorization** on each export.

### Device Binding
- **FR-15** Register a device on login (**Device ID, OS, App Version, IP, Country, Last Login, Last Active**) and enforce a **max of 2 active devices**.
- **FR-16** On a 3rd device, show registered devices and let the user **remove one or buy an extra slot**; users can view/remove their own devices in settings.

### Notifications
- **FR-17** Transactional emails: verify email, reset password, payment confirmation, **subscription expiry reminder**. In-app notices for subscription expired, export limit reached, device limit reached.

### Admin Panel (web)
- **FR-18** Role-gated admin login. Manage templates (create, upload assets, edit metadata, publish/unpublish, delete) and **define per-template editable fields** with defaults and constraints.
- **FR-19** Manage users (view, search, suspend, adjust subscription) and devices (view, revoke).
- **FR-20** View subscriptions & payments; **reports** (active subscribers, USDT revenue, exports, signups) and **audit logs**.

---

## 4. Non-Functional Requirements

| Area | Requirement |
|------|-------------|
| **Performance** | Metadata API responsive under normal load on the target VPS; template lists paginated. On-device export budget defined in `03-architecture`. |
| **Security** | Per Decision Record §6 — Argon2, JWT+refresh, HTTPS, RBAC, rate limiting, input validation, parameterized queries, audit logs, private storage, signed URLs, encrypted local storage, SSL pinning, root/jailbreak/tamper detection, env-var secrets. |
| **Reliability** | Daily automated DB + assets backup with a documented restore procedure. Binance webhook handling is idempotent. |
| **Maintainability** | One developer can run the whole stack via `docker compose up`. Direct code, no needless abstractions. |
| **Usability** | Modern, premium, minimal UI. Light + dark mode. Responsive web. |
| **Compatibility** | Android + iOS (min versions set in `03-architecture`); modern browsers for web/admin. |

---

## 5. Business Rules

- **BR-1** A subscription is active only after a **backend-verified** Binance Pay payment.
- **BR-2** Premium editing/export requires an **active** subscription at request time.
- **BR-3** Export is allowed only while **exports remaining > 0** and subscription is active.
- **BR-4** Max **2 active devices**; a 3rd requires removing one or buying a slot.
- **BR-5** On expiry, premium capability locks immediately; account and data are retained.
- **BR-6** Renewal is **manual**; there is no auto-charge.
- **BR-7** Original template assets are **never** public — served only via short-lived signed URLs to entitled devices.
- **BR-8** Every Binance webhook is signature-verified and processed **once** (idempotent).
- **BR-9** Admin actions on users/devices/subscriptions are **audit-logged**.

---

## 6. Editable Fields (approved scope)

All fields approved by the client are in scope for Version 1. The architecture (data model + editor + FFmpeg render) will be designed to support all of them:

| Field | Type |
|-------|------|
| **Logo** | Image overlay onto an admin-defined slot |
| **Title** | Text |
| **Subtitle** | Text |
| **Fonts** | Selectable from admin-provided fonts |
| **Colors** | Color selection |
| **Text Size** | Size control |
| **Text Position** | Position control |
| **Visibility** | Show/hide a field |

Per template, the admin defines which of these are editable, their defaults and constraints.

> 💡 **Recommendation (not a decision):** for **Text Size** and **Text Position**, offering preset options (e.g. S/M/L; top/center/bottom anchors) instead of free-form pixel control would reduce render edge-cases and development effort. This is only a suggestion — **default plan is to implement the full approved controls** unless the client chooses the preset approach.

---

## 7. Subscription Plans — Placeholders (Pending Client Confirmation)

Pricing and limits are **not finalized**; placeholders below unblock documentation. Real values set later by the client.

| Plan | Price (USDT) | Export limit | Device limit | Validity |
|------|-------------|--------------|--------------|----------|
| **Monthly** | `<placeholder>` | `<placeholder>` | 2 | `<placeholder>` |
| **Yearly** | `<placeholder>` | `<placeholder>` | 2 | `<placeholder>` |

Extra-device-slot price: `<placeholder>`. Device limit fixed at 2 per Decision Record.

---

## 8. Assumptions
1. English-only launch.
2. Client provides the Binance Pay merchant account and all template source assets.
3. A "template" = base asset(s) + admin-defined editable-field metadata; the device renders the final MP4.
4. Fonts and palettes are admin-provided and licensing-cleared by the client.
5. Single VPS; daily backups acceptable.
6. Guest/free previews are low-res/watermarked versions the admin uploads.

---

## 9. Out of Scope
- Any payment method other than Binance Pay.
- Auto-renew / recurring billing.
- Server-side video rendering.
- Social features (feeds, comments, profiles).
- User/marketplace template selling.
- Multi-language localization.
- Native (non-Flutter) apps.
- Object storage, Redis, queues, workers, microservices, Kubernetes.
- Cloud device farms / additional test frameworks.
- Analytics/monitoring beyond app + audit logs.

---

## 10. Pending Client Confirmation
1. **Plan structure, prices, export limits, validity durations** (§7) and extra-device-slot price.
2. **Text Size / Text Position** — full controls (default) or preset approach (§6 recommendation)?
