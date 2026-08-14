# ClipCart — Feature Logic & Functional Completeness

> Principal-engineer / PM / QA view: for **every feature**, the real logic, the backend functions/endpoints it needs, edge cases, and "done-when". This catches the *basic-but-essential* pieces that a screen mock alone hides (e.g. **admin must watch the video before approving**). Governs the build.

---

## 0. Gaps caught in this pass (the "basic" things)
1. **Admin review = watch the video.** The review screen must **play the preview** (and open the original privately), show all metadata + the editable-field config, then Approve / **Reject with reason** / **Request changes with notes**. Nothing goes live unapproved.
2. **Editor resubmission loop.** Reject / request-changes → editor edits → re-enters the queue (status history kept).
3. **Export accounting.** Server **authorizes** each export (atomic limit check + decrement), the app renders on-device, then **confirms completion** → records download history + increments the clip's download count + accrues editor earnings. **Failed render → refund the export credit.**
4. **Plan-terms snapshot.** A subscription stores the plan's terms *at purchase time*, so later admin edits to a plan don't retroactively change active subscribers.
5. **Export-limit reset** is period-based (per subscription month), computed by boundary, not a nightly job.
6. **Upgrade = new purchase supersedes** (no proration — consistent with crypto/manual).
7. **Preview/thumbnail are uploaded by the editor** (server never renders); original template stays private, delivered only to entitled devices.
8. **Webhook idempotency** keyed on Binance order id (retries safe).
9. **Trending / Featured / Newest** are explicit computed/curated lists, not vague.
10. **Withdrawal** = editor requests → threshold check → admin approves → manual settlement → recorded.
11. **Concurrent review claim** so two admins don't act on the same item.
12. **Signed-URL TTL + entitlement re-check** on every premium asset fetch.
13. **Managed lookup lists**: categories, genres, languages (admin-curated), used by upload + filters.
14. **Quality/aspect ratio gated by plan** (720/1080/4K, watermark for free).

---

## 1. Auth & Account
**Logic:** register → email verification (required before login) → login issues JWT access + refresh, registers device → refresh rotation → logout revokes refresh on that device. Forgot/reset via single-use, expiring token. Change password re-auths and invalidates other refresh tokens.
**Functions:** `POST /auth/register`, `/auth/verify`, `/auth/resend-verify`, `/auth/login`, `/auth/refresh`, `/auth/logout`, `/auth/forgot`, `/auth/reset`; `GET/PATCH /me`, `POST /me/password`.
**Edge:** duplicate email; login while unverified; expired/used tokens; brute-force → per-IP + per-account rate limit + temporary lockout; weak password rejected; resend throttle.
**Done-when:** all flows + transactional emails + rate limits + tests green.

## 2. Roles & RBAC (customer · editor · admin)
**Logic:** every protected endpoint runs an auth+role guard. Admin creates editor accounts via email invite (editor sets own password). Role is server-authoritative; UI state is convenience only.
**Functions:** role dependency guards; `POST /admin/editors` (invite), `POST /auth/accept-invite`.
**Edge:** privilege checks on *every* editor/admin route; suspended account blocked; invite token expiry.

## 3. Subscription, Plans & Payment
**Logic:** admin CRUD plans (name, price USDT, export limit, quality cap, device limit, features, active flag). Customer subscribes → backend creates **Binance Pay** order → user pays → **signed webhook** verified + idempotent → subscription activated with a **snapshot** of plan terms + expiry. Manual renewal extends. Upgrade = new purchase supersedes remaining term. On expiry → premium locks (lazy check at request time). Export counter resets each subscription-month. **Invoice** generated on each verified payment.
**Functions:** admin `GET/POST/PATCH/DELETE /admin/plans`; `GET /plans`; `POST /subscriptions/checkout`; `POST /webhooks/binance` (verify sig, idempotent by order id); `GET /subscriptions/me`; `GET /invoices`, `GET /invoices/{id}`.
**Edge:** webhook retries/duplicates; underpaid/expired order; race on activation; plan edited after purchase (snapshot protects); expiry timezone; limit-reset boundary; refund/chargeback N/A (crypto).
**Done-when:** sandbox end-to-end, idempotent, invoices, limit enforcement, upgrade path.

## 4. Clip Upload, Metadata & Storage (editor)
**Logic:** editor uploads **original template** (private), **preview** (watermarked/low-res), **thumbnail**, plus metadata: title, description, category, **movie name, genre, language**, tags, duration, resolution, aspect ratio, tier (free/premium). Editor sets the **editable-field config** (which fields customers may change + defaults/constraints). Saved as `pending review`.
**Functions:** `POST /editor/clips` (multipart, validation), asset store (private originals, public-via-signed previews), `PATCH /editor/clips/{id}`, `DELETE` (if not live).
**Edge:** file type/size validation, malformed media, missing required metadata, storage cleanup on delete/reject, duplicate title, aspect-ratio/resolution sanity.
**Done-when:** validated upload + private original + signed preview + full metadata + field config.

## 5. Admin Review System  ⭐ (the flagged gap)
**Logic:** every upload enters the **review queue**. Admin opens the item, **plays the preview video** (and can open the private original), reviews all metadata + editable-field config, then:
- **Approve** → status `live` (optionally **Feature** it) → appears in customer library + editor notified.
- **Request changes** → status `changes_requested` + **notes** → editor edits → re-queues.
- **Reject** → status `rejected` + **reason** → editor notified; may duplicate/resubmit.
Every decision is **audit-logged**; status history retained. A **claim/lock** prevents two admins acting on the same item.
**Functions:** `GET /admin/review-queue`, `GET /admin/clips/{id}` (returns signed preview URL + meta), `POST /admin/clips/{id}/approve` (+featured?), `/request-changes` (notes), `/reject` (reason), `POST /admin/clips/{id}/claim`. Notification + audit on each.
**Edge:** preview fails to load; re-review after resubmit; concurrent claim; large video; approve then need to unpublish.
**Done-when:** reviewer can watch + decide with reason/notes; editor sees outcome; nothing live without approval.

## 6. Home, Browse, Search, Filters, Favorites (customer)
**Logic:** Home = **Featured** (admin-curated) + **Newest** (by approval date) + **Trending** (top downloads/views in a rolling window) + categories + search + pricing + testimonials + CTA. Library grid shows thumbnail, category, tags, duration, resolution, upload date, popularity, # downloads. **Filters:** category, movie, genre, editor, duration, newest, most popular, trending, language, premium/free. Favorites = save/unsave + list. Non-subscribers see gated previews only.
**Functions:** `GET /home`, `GET /clips?filter&sort&page&q`, `GET /clips/{id}`, `POST/DELETE /favorites/{clipId}`, `GET /favorites`, `GET /lookups` (categories/genres/languages).
**Edge:** empty states; pagination; premium lock overlay; search relevance; trending window recompute cadence.

## 7. Preview
**Logic:** watermarked, lower-quality, time-limited playback via short-TTL signed URL. Subscribers still preview before customizing. Original never exposed.
**Functions:** `GET /clips/{id}/preview` → signed URL.

## 8. Customize — **Layer Editor** (mobile app · on-device)
A **layer-based overlay editor** on top of a **fixed base clip** (admin's template). The customer does NOT trim/cut/re-order video — they add & edit **overlay layers** on the clip. This matches the client-doc customization list (subtitle/logo/username/CTA/ending-screen/… = layers). It is **NOT** a general video editor (no trim/split, no multi-track audio, no AI clipper).

**Layer types (admin enables per clip):**
- **Subtitle** — a **timed track**: multiple lines, each with **start–end time**, text, font, size, color, stroke, background, position. This is the key ask (captions at different timestamps). ⭐
- **Logo · Username · CTA · Ending screen · Watermark** — single overlay layers, positioned + styled (some can also be timed if admin enables).

**Logic:** entitled subscriber opens editor → app fetches the **base clip** (entitlement + subscription + device re-checked, signed URL) → shows **live preview**: a video player + overlay widgets whose visibility/content is driven by the **current playback time** (each subtitle segment shows only within its [start,end]). Customer edits layers + subtitle segments (add/edit text, set timing via the track, style). All validated against admin config (allowed fonts/colors, max length, etc.).

**Preview (how timing works live):** `video_player` + positioned overlay `Text`/image widgets; a ticker compares playhead time to each layer's time window → shows/hides. No full compositing engine needed (overlays only, base video fixed).

**Functions:** `GET /clips/{id}/template` (guarded → signed URL); layer + subtitle-segment config from clip metadata (`subtitles: [{text,start,end,style,position}]`, plus logo/username/cta/ending layer defs).
**Edge:** entitlement revoked mid-session; download failure/retry; device limit; input beyond constraints; overlapping subtitle times; segment outside clip duration; font/color not in allowed set.
**Explicitly OUT of scope:** trimming/splitting the base clip, multi-track audio editing, AI auto-clipping, cover/thumbnail generation (that's the admin's job).

## 9. Export (on-device FFmpeg)
**Logic:** `POST /exports/authorize` re-validates **auth + subscription + device + export-limit remaining**, **atomically decrements** the counter, returns template access + target quality (plan cap) + watermark flag. App builds an **FFmpeg filtergraph** compositing all layers onto the base clip and renders MP4 on-device. `POST /exports/complete` records the export → **download history + clip download count + editor earnings accrual**. If render fails → `POST /exports/refund` restores the credit.
**Rendering the layers (FFmpeg):**
- **Timed subtitles** → generate an **ASS file** from the subtitle segments (per-line start/end + font/color/stroke/position) and burn with `subtitles=captions.ass`. (Alternative: chained `drawtext` with `enable='between(t,start,end)'` per segment.)
- **Logo / image layers** → `overlay` filter (with `enable='between(t,a,b)'` if timed).
- **Static text (username/CTA/ending)** → `drawtext` (timed via `enable` where needed).
- Layers composited in order (base → subtitles → logo → CTA → ending). Confirmed supported by FFmpeg docs.
**Functions:** `/exports/authorize`, `/exports/complete`, `/exports/refund`.
**Edge:** limit hit → block + upsell; concurrent exports; crash after decrement → refund; offline; quality above plan → clamp.
**Done-when:** counting exact, payout attribution correct, history recorded, failure-safe.

## 10. Download History
**Logic:** list customer exports (clip, date, quality, aspect). Re-download re-renders on-device from saved settings (server keeps no finished file long-term; temp exports auto-expire).
**Functions:** `GET /downloads`; saved export settings per record.

## 11. Notifications
**Logic:** in-app + email on key events. **Customer:** new clips, renewal reminder, export complete (local), payment confirmation. **Editor:** upload approved / rejected / changes-requested, new download, payout processed.
**Functions:** event → notification write; `GET /notifications`, `POST /notifications/read`. Email via SMTP for verify/reset/payment/payout.
**Edge:** no push infra (in-app + email only); de-dupe; unread counts.

## 12. Editor Dashboard, Earnings & Payouts
**Logic:** track total uploads, approved, pending, changes-requested, rejected, downloads, earnings. **Earnings** accrue per download of approved clips (rate/revenue-share = business setting). Editor **requests withdrawal** (≥ threshold) → admin approves → **manual settlement** → recorded as paid.
**Functions:** `GET /editor/dashboard`, `GET /editor/clips`, `GET /editor/earnings`, `POST /editor/withdrawals`, `GET /editor/withdrawals`.
**Edge:** withdrawal below threshold; double request; earnings only on approved+live clips; reversal if download invalidated.

## 13. Admin Management, Payouts, Analytics, Settings
**Logic:** manage customers (view/search/suspend/adjust sub), editors (create/suspend/role), review queue (§5), clips (feature/unpublish/delete), **plans CRUD + pricing**, payments (verified list), **payouts (approve/mark paid)**, **categories/genres/languages CRUD**, **analytics** (total customers, active subs, revenue, daily exports, most-downloaded, top editors, customer growth, MRR), audit logs, platform settings.
**Functions:** the admin endpoints above + `GET /admin/analytics`, `GET /admin/audit`, category/lookup CRUD, `POST /admin/payouts/{id}/paid`.
**Edge:** suspend cascades (block login/exports); delete vs unpublish; MRR approximate under manual-renewal.

## 14. Device Binding
**Logic:** on login register device (id, os, app version, ip, country, last login/active). Enforce plan device-limit; 3rd → manage/remove or buy slot. Admin can revoke. Every protected request validates the device.
**Functions:** device register on login; `GET /me/devices`, `DELETE /me/devices/{id}`; admin revoke; device-check middleware.
**Edge:** limit reached at login; removed device's tokens invalidated; spoofed device id (bind to install + token).

## 15. Security (cross-cutting)
Argon2; JWT access + refresh (rotation + revocation); HTTPS (Caddy); RBAC; rate limiting; input validation; parameterized queries (ORM); audit logs; private storage + short-TTL signed URLs; encrypted local storage + secure token storage (Keychain/Keystore); Flutter obfuscation; SSL pinning; root/jailbreak/tamper detection; env-var secrets; Binance webhook signature verification. Every premium request validates **auth + subscription + device + authorization**.

---

## New screens this analysis implies (to add to UX + prototype)
- **Admin: Review Detail** (video player + metadata + approve/reject-reason/request-changes) ⭐
- **Admin: Plans management** (CRUD, pricing, limits, quality)
- **Admin: Categories / Genres / Languages** management
- **Customer: Invoices** (list + view)
- **Editor: Clip status detail** (rejected reason / changes notes + resubmit)
- **Editor: Withdrawal request** flow (threshold, confirm)
- **Customer: rich Filters** (movie/genre/editor/language/duration/premium)
