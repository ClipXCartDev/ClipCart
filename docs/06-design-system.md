# ClipCart — Design System

> Phase 3 deliverable. Concrete design tokens + component specs that map directly to Flutter. Goal: **modern, premium, minimal, professional** — implemented with **one typeface, one icon set, one tokens file, zero extra packages**. Wireframes & hi-fi screens come in Phase 4; this defines the building blocks they use.

**Implementation model:** all tokens live in one Dart file (`lib/theme/tokens.dart`) and feed two `ThemeData` objects (light + dark). No theming package, no design framework. Direct.

**Framework:** **Material 3** base theme with ClipCart's custom premium branding on top (same approach as Canva/Spotify/Notion). The visual branding is **identical on Android, iOS and web**; only platform-native transitions differ — Material page transitions on Android, Cupertino transitions on iOS (Flutter's adaptive defaults). No separate design per platform.

**Motion:** subtle only — fade, scale, slide (150–250ms per §8). No elaborate/decorative animation.

---

## 1. Brand & tone
Premium creative tool. **Light is the default theme; dark is fully supported** via a simple toggle in Settings (no system-theme detection). Minimal surfaces, generous spacing, one confident accent, restrained motion. Nothing decorative that doesn't serve the content (the templates are the hero).

---

## 2. Color tokens

Single accent (**Iris/Violet**) + neutral system + semantic colors + one sparing **premium gold** used only for subscription/premium cues (the product literally sells "premium").

### 2.1 Accent & semantic (shared across themes)
| Token | Hex | Use |
|-------|-----|-----|
| `primary` | `#7B61FF` | Primary actions, active states, links. |
| `primaryPressed` | `#6249E0` | Pressed/hover of primary. |
| `primarySubtle` | `#7B61FF` @ 12% | Tinted backgrounds, selected chips. |
| `onPrimary` | `#FFFFFF` | Text/icon on primary. |
| `premium` | `#E4C05C` | Premium/subscription badges only (sparingly). |
| `success` | `#2FBF71` | Success states, active subscription. |
| `warning` | `#E8A13A` | Warnings, expiring soon. |
| `danger` | `#E5484D` | Errors, destructive actions, expired. |
| `info` | `#4C9AFF` | Neutral info notices. |

### 2.2 Neutrals — Dark theme (default)
| Token | Hex |
|-------|-----|
| `bg` | `#0B0B0F` |
| `surface` | `#141419` |
| `surfaceElevated` | `#1C1C24` |
| `border` | `#2A2A33` |
| `textPrimary` | `#F5F5F7` |
| `textSecondary` | `#A0A0AB` |
| `textTertiary` | `#6B6B76` |

### 2.3 Neutrals — Light theme
| Token | Hex |
|-------|-----|
| `bg` | `#FAFAFB` |
| `surface` | `#FFFFFF` |
| `surfaceElevated` | `#FFFFFF` (+ shadow) |
| `border` | `#E6E6EB` |
| `textPrimary` | `#111114` |
| `textSecondary` | `#5A5A66` |
| `textTertiary` | `#9A9AA5` |

> Accent & semantic hexes stay the same in both themes; only neutrals swap. Keeps the palette small and consistent.

---

## 3. Typography

**One typeface: Plus Jakarta Sans** (premium, modern, free). Bundled as font **assets** (no `google_fonts` package → no runtime fetch, plays well with SSL pinning/offline). Weights: 400, 500, 600, 700, 800.

| Style | Size / Line | Weight | Use |
|-------|-------------|--------|-----|
| `displayL` | 32 / 40 | 800 | Hero/landing headline. |
| `displayM` | 28 / 36 | 700 | Screen titles. |
| `heading` | 22 / 28 | 700 | Section headers. |
| `title` | 18 / 24 | 600 | Card titles, dialog titles. |
| `bodyL` | 16 / 24 | 400 | Primary body. |
| `bodyM` | 14 / 20 | 400 | Secondary body, list text. |
| `label` | 14 / 20 | 600 | Buttons, tabs, labels. |
| `caption` | 12 / 16 | 500 | Meta, timestamps, helper text. |

Supports OS text scaling (accessibility). Never hardcode font sizes outside these tokens.

---

## 4. Spacing, radius, elevation

**Spacing** — 4px base scale: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. Default screen padding **16** (mobile), **24** (web content).

**Radius:** `sm 8` · `md 12` (default: buttons, inputs, cards) · `lg 16` (sheets, large cards) · `xl 20` · `full 999` (pills, avatars).

**Elevation** (3 levels): dark theme prefers surface tint over shadow; light theme uses soft shadows.
| Level | Dark | Light |
|-------|------|-------|
| `e0` flat | `surface` | `surface`, no shadow |
| `e1` card | `surfaceElevated` | shadow y2 blur8 @6% |
| `e2` dialog/sheet | `surfaceElevated` + border | shadow y8 blur24 @12% |

---

## 5. Grid & responsive layout

| Context | Rule |
|---------|------|
| **Mobile** | Single column, 16 page padding, 8 gutter. Template grid **2 columns**. |
| **Web breakpoints** | mobile `<600`, tablet `600–1024`, desktop `>1024`. Max content width **1200**, centered. |
| **Web template grid** | 2 / 3 / 4 columns by breakpoint. |
| **Admin** | Fixed **left sidebar 240px** + fluid content; tables scroll horizontally inside their container on small widths. |

---

## 6. Component library

Core reusable components (built once, used everywhere). States listed are mandatory.

| Component | Variants / States | Used in |
|-----------|-------------------|---------|
| **Button** | primary · secondary · ghost · danger; sizes sm/md/lg; states: default, hover/pressed, disabled, **loading** | Everywhere |
| **Text field** | text · password (show/hide) · with error/helper; states: default, focus, error, disabled | Auth, profile, admin |
| **Select / Dropdown** | single-select; searchable variant | Filters, admin, editor (fonts) |
| **Search bar** | with clear button | Library (M7/W6), admin lists |
| **Filter chips** | default / selected | Library category filter |
| **Template card** | thumbnail, title, premium badge, lock overlay (non-subscriber) | Library, detail |
| **Card** | info card, stat card (admin dashboard) | Account, admin |
| **List tile** | device row, payment row, settings row; with trailing action | Devices, history, settings |
| **Badge** | status (active/expired/expiring) using semantic colors; **premium** (gold) | Subscription, template card |
| **Dialog** | confirm / alert; primary + cancel | Delete, revoke device, logout |
| **Bottom sheet** (mobile) | actions / pickers | Editor pickers, device actions |
| **Snackbar / Toast** | success / info / error | Global feedback |
| **Banner** | paywall / locked-state / notice | M15 paywall, expiry notices |
| **Segmented control** | 2–3 options | Text size/position presets (if chosen) |
| **Slider** | single value | Editable text size (full-control mode) |
| **Color swatch picker** | admin-defined palette swatches | Editor (colors), admin |
| **Empty state** | icon + text + optional CTA | Empty library, no devices, no payments |
| **Skeleton loader** | list/grid placeholder | Library, dashboards |
| **Avatar** | image / initials fallback | Profile, app bar |
| **Navigation** | mobile bottom nav (2 tabs) · web top nav · admin left sidebar · app bar | Shells |
| **Progress** | linear (export) + spinner | Export (M10), checkout wait |

> The editor's field controls (logo picker, text input, font select, color swatches, size, position, visibility toggle) are compositions of the above — no bespoke widgets beyond what's listed.

---

## 7. Iconography
**Material Symbols Rounded** — the rounded set gives the premium, modern feel (client-approved for that reason). Implemented via the single `material_symbols_icons` package (one well-maintained package, justified by the premium requirement). One consistent set across mobile + web + admin. Icon sizes: 20 (inline), 24 (default), 28 (nav).

---

## 8. Motion
Minimal and fast. Durations: **150ms** (small state changes), **250ms** (page/sheet transitions). Standard ease-in-out. No decorative animation. Export progress uses a real determinate/indeterminate indicator, not a fake timer.

---

## 9. Accessibility (practical AA)
- Text contrast ≥ **4.5:1** (verified for all text-on-surface token pairs).
- Minimum tap target **48×48**.
- Visible **focus** state on all interactive elements (keyboard/web).
- Never rely on color alone — pair status colors with icon/label (e.g. "Expired" text + danger color).
- Respect OS text scaling; layouts must not clip at 1.3× text size.
- All inputs have labels; images/icons that convey meaning have semantics labels.

---

## 10. Theming rules (for developers)
- **Every color/type/spacing value comes from a token.** No inline hex, no magic numbers in widgets.
- Two `ThemeData` (light/dark) built from the same token maps; theme switch is a single toggle in Settings, stored in encrypted local prefs.
- Default theme = **light**. No system-theme detection; user toggles manually.
- Components read from `Theme.of(context)` extensions — one place to change, everywhere updates.

---

## 11. Branding (locked for build)
- **Accent color:** Iris/Violet **`#7B61FF`** (locked; replaceable if client sends a brand color later).
- **Logo:** **placeholder wordmark** used throughout; swap in client branding later without other changes.
