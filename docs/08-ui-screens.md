# ClipCart — UI Screens (Phase 4)

> Directly-implementable Flutter screen specs. Each screen = **layout + components (from `06-design-system.md`) + states**. Compact ASCII wireframes show structure only; visual styling comes entirely from the design tokens. Screen IDs match `02-ux-flows.md`. Default theme = **light**. No new features, no product decisions.

**How to read:** `[Button]` = primary button, `[ Field ]` = text field, `( )` = icon, `▸` = list row. Components are the Phase 3 ones — no bespoke widgets.

---

## 1. Global patterns (built once, reused)

### 1.1 Mobile app shell
- **App bar:** left = screen title / back; right = (notifications) bell → M14, (avatar) → Account.
- **Bottom nav (2 tabs):** `Templates` · `Account`. Editor/Export are pushed full-screen (no bottom nav).
- Page padding 16, safe-area aware.

### 1.2 Auth layout (shared by M2–M6, W3–W5)
```
┌───────────────────────────┐
│         ClipCart          │  ← wordmark, centered top
│                           │
│   Screen title (displayM) │
│   subtitle (bodyM)        │
│                           │
│   [ Field 1 ]             │
│   [ Field 2 ]             │
│   helper / error (caption)│
│                           │
│   [   Primary button   ]  │  ← full width, loading state
│                           │
│   secondary link (label)  │  ← e.g. "Forgot password?"
└───────────────────────────┘
```
One reusable `AuthScaffold(title, subtitle, fields, primaryAction, footer)` renders every auth screen. Only field set + actions differ.

### 1.3 Web shell
- **Public top nav:** wordmark · Home · Pricing · [Login] [Register]. Sticky, max-width 1200 centered.
- **Account shell:** left mini-nav or top tabs (Dashboard · Payments · Devices · Profile) + content.
- Responsive per Phase 3 breakpoints.

### 1.4 Admin shell
- **Left sidebar 240px:** wordmark, nav (Dashboard · Templates · Users · Payments · Reports · Audit Logs), footer = admin avatar + logout.
- Content area: page title + primary action top-right, then table/form.

---

## 2. Mobile screens

### M1 — Splash + security check
Centered wordmark + subtle spinner. Runs root/jailbreak/tamper + SSL checks. On pass → route (session? Library : Login). On fail → blocking dialog (danger) "This device isn't supported", no bypass.

### M2–M6 — Auth (use AuthScaffold)
| Screen | Fields | Primary | Footer |
|--------|--------|---------|--------|
| **M2 Login** | Email, Password (show/hide) | `Log in` | "Forgot password?" · "Create account" |
| **M3 Register** | Name, Email, Password | `Create account` | "Have an account? Log in" |
| **M4 Verify email** | *(no fields)* — icon + "Check your inbox" | `Resend email` | "Back to login" |
| **M5 Forgot password** | Email | `Send reset link` | "Back to login" |
| **M6 Reset password** | New password, Confirm | `Reset password` | — |

States for all: field validation errors inline; primary shows loading; server error → snackbar.

### M7 — Template Library (Home)
```
┌───────────────────────────┐
│ Templates        ( ) ( )  │  app bar: bell, avatar
│ [ (search) Search…      ] │
│ [All][Promo][Intro][…]    │  ← filter chips (horizontal scroll)
│ ┌─────────┐ ┌─────────┐   │
│ │ thumb   │ │ thumb   │   │  ← template cards, 2 cols
│ │ Title ⭐│ │ Title 🔒│   │     ⭐=premium badge, 🔒=locked
│ └─────────┘ └─────────┘   │
│ ┌─────────┐ ┌─────────┐   │
│ …                         │
└───────────────────────────┘
```
States: skeleton grid (loading), empty state (no results), paginated infinite scroll. Non-subscriber sees lock overlay on premium cards.

### M8 — Template Detail
Top: preview video player (low-res for non-subscribers) + title + premium badge. Below: description, "Editable: Title, Logo, Colors…" summary chips. Sticky bottom CTA:
- Subscriber + exports left → `[ Edit template ]`
- Non-subscriber → `[ Subscribe to edit ]` → opens M15 paywall.

### M9 — Editor
```
┌───────────────────────────┐
│ ( ←)  Edit         [Export]│
│ ┌───────────────────────┐ │
│ │   live preview        │ │  ← on-device render preview
│ │                       │ │
│ └───────────────────────┘ │
│ Fields (scroll):          │
│ ▸ Title      [ text     ] │
│ ▸ Subtitle   [ text     ] │
│ ▸ Logo       ( upload )   │
│ ▸ Font       [ select ▾ ] │
│ ▸ Color      ◐ ◑ ◒ ◓      │  ← swatch picker (admin palette)
│ ▸ Text size  ──●──        │  ← slider (or segmented if preset)
│ ▸ Position   [T][C][B]    │  ← segmented (or free if full-control)
│ ▸ Visible    ( toggle )   │
└───────────────────────────┘
```
Only fields the admin enabled render (each is a Phase 3 component). Live preview updates on change. `Export` in app bar → M10.

### M10 — Export
Full-screen: preview thumbnail + linear progress ("Rendering… 42%") using real FFmpeg progress. On done: success state + `[ Save to device ]` `[ Share ]`. Decrements export count. If limit hit before start → block with notice → M15. Cancel returns to editor.

### M11 — Subscription Status (read-only)
Card: plan name, status badge (active/expired/expiring), expiry date, exports remaining (e.g. "18 / 30"). If expired/none → `[ Renew on website ]` (opens web). No in-app purchase.

### M12 — Devices
List of device rows: `▸ Device name · OS · app version · last active` + (remove) trailing. Header caption "2 of 2 devices". Remove → confirm dialog. If at limit during a new login, this screen shows with the new device pending.

### M13 — Profile & Settings
Sections as list tiles: **Profile** (name, avatar, email read-only) · **Security** (Change password) · **Appearance** (Light/Dark toggle) · **Notifications** · **Devices** → M12 · **Subscription** → M11 · **Logout** (danger). 

### M14 — Notifications
Simple list of in-app notices (icon + text + time), backend-driven: subscription expired, export/device limit reached. Empty state when none.

### M15 — Paywall / Locked
Banner-style full screen: premium icon (gold), "Subscribe to unlock editing & export", short benefit list, `[ Subscribe on website ]`. Read-only, points to web.

---

## 3. Website screens

### W1 — Landing
Hero: wordmark, headline (displayL), subline, `[ View plans ]` `[ Log in ]`. Below: 3 concise value points + a template preview strip. Footer: links (incl. Support/Contact if enabled).

### W2 — Pricing / Plans
Two plan cards (Monthly / Yearly) side by side (stacked on mobile): plan name, price (placeholder), export limit, device limit, validity, `[ Subscribe ]`. Premium styling on the recommended card.

### W3–W5 — Auth (reuse AuthScaffold, web-centered card, max-width 420)
Register / Login / Verify / Forgot / Reset — same fields as mobile M2–M6.

### W6 — Template Library
Responsive grid (2/3/4 cols), search + filter chips (same as M7). Cards link to W7. Previews low-res/watermarked.

### W7 — Template Detail
Preview + description + editable-fields summary. CTA: non-subscriber → `[ Subscribe ]` (→ W2/W8); subscriber → info note "Edit & export in the ClipCart mobile app" (no web editor).

### W8 — Checkout (Binance Pay)
```
┌──────────────────────────────────┐
│  Order summary                   │
│  Plan: Yearly     $<placeholder> │
│  ───────────────────────────────  │
│  [   Pay with Binance Pay   ]    │  ← creates order, opens Binance Pay
│  Status: waiting for payment…    │  ← polls/awaits backend verification
└──────────────────────────────────┘
```
Never marks paid from frontend. Shows pending until backend confirms webhook → routes to W9.

### W9 — Payment Result
Three states: **Success** (green, "Subscription active", `[ Go to dashboard ]`), **Pending** ("We'll activate once confirmed"), **Failed/expired** (`[ Try again ]`). Driven only by backend status.

### W10 — Account Dashboard
Subscription card (status, expiry, exports left) + `[ Renew ]` + quick links to Payments / Devices / Profile.

### W11 — Payment History
Table/list: date · plan · amount (USDT) · status. Empty state when none. Read from verified payments only.

### W12 — Devices
Same as M12 (rows + remove). Plus, if at limit: `[ Buy extra device slot ]` → Binance Pay flow (same as W8) *(pending confirmation per Phase 2 §7)*.

### W13 — Profile & Settings
Profile fields, change password, Light/Dark toggle, logout.

### W14 — Support / Contact *(optional, pending confirmation)*
Static page: contact email / form, basic FAQ. Only if client opts in.

---

## 4. Admin screens

### A1 — Admin Login
AuthScaffold variant, role-gated. Email + password → admin shell.

### A2 — Dashboard
Row of 4 stat cards: Active subscribers · Revenue (USDT) · Exports · New signups. Below: a simple recent-activity list. No charts required for v1 (stat cards + counts; a basic trend list is enough).

### A3 — Templates List
Toolbar: search + `[ + New template ]`. Table: thumbnail · title · category · status(published/draft) · actions (edit, publish/unpublish, delete). Pagination.

### A4 — Template Editor
```
┌───────────────────────────────────────┐
│ New / Edit Template          [ Save ]  │
│ ┌─── Assets ─────────────────────────┐ │
│ │ Template file  ( upload )          │ │
│ │ Preview video  ( upload )          │ │
│ │ Thumbnail      ( upload )          │ │
│ └────────────────────────────────────┘ │
│ Title      [                        ]  │
│ Description[                        ]  │
│ Category   [ select ▾ ]  Tags [ + ]    │
│ Status     ( Draft ) ( Published )     │
│ → Configure editable fields  (A5)      │
└───────────────────────────────────────┘
```

### A5 — Editable Fields Config
Per template: list of the 8 field types, each with `enable` toggle + default value + constraints (e.g. max text length, allowed colors from palette, allowed fonts). Save writes the field metadata the mobile editor reads.

### A6 — Users List
Search + table: email · name · subscription status · signup date · actions (view). Pagination.

### A7 — User Detail
User info + subscription panel (plan, expiry, `Adjust` / `Suspend`) + **Devices** sub-list with (revoke) per device. All actions confirm + audit-logged.

### A8 — Subscriptions & Payments
Table: user · plan · amount (USDT) · date · status (verified). Filter by status/date. Read-only records.

### A9 — Reports
Simple counts + a basic period selector (e.g. last 7/30 days): subscribers, revenue, exports, signups. Plain tables/numbers — no heavy charting library (stays within stack).

### A10 — Audit Logs
Table: timestamp · actor · action · target · IP. Search/filter by actor/action. Read-only.

---

## 5. Cross-cutting states (apply everywhere)
- **Loading:** skeletons for lists/grids; button loading for actions.
- **Empty:** every list/grid has an empty state (icon + message + optional CTA).
- **Error:** inline for form fields; snackbar for actions; full-screen retry for page-load failure.
- **Offline (mobile):** cached library where available; clear "You're offline" banner; export blocked with notice (needs asset + entitlement check).
- **Permission/entitlement:** protected actions re-check server-side; on failure show the relevant notice (expired → M11/W10, limit → M15).

---

## 6. Implementation notes
- Reuse `AuthScaffold`, `TemplateCard`, `ListTileRow`, `StatCard`, `StatusBadge`, `EmptyState`, `AppButton`, `AppTextField` — the whole UI is these + layout.
- No screen introduces a widget not in the Phase 3 component list.
- Wireframes convey structure only; spacing, color, type come from tokens — do not hardcode.
- These specs + `06-design-system.md` are sufficient to implement every screen without external design files.
