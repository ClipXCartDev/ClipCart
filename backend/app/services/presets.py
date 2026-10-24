"""The caption presets the app offers, and the defaults it falls back to.

A preset is a complete caption look: font, size, colour, weight, alignment,
stroke, background, shadow, opacity and motion. Complete on purpose - the old
presets set five fields and left the rest alone, so applying one gave a
different result depending on what the caption looked like before.

These live here rather than in the app so they can be changed without a
release. The app ships the same list as its own fallback, for a first run with
no network; the two agree until an admin changes one.
"""
from __future__ import annotations

from typing import Any

from sqlalchemy.orm import Session

from app.models.settings import CAPTION_PRESETS, AppSetting

#: Every value a preset decides, and what it is when a preset does not say.
FIELD_DEFAULTS: dict[str, Any] = {
    "font": None,
    "fontSize": 44.0,
    "color": "#FFFFFFFF",
    "bold": True,
    "italic": False,
    "align": "center",
    "letterSpacing": 0.0,
    "lineHeight": 1.15,
    "strokeWidth": 0.0,
    "strokeColor": "#FF000000",
    "bgEnabled": False,
    "bgColor": "#00000000",
    "shadow": False,
    "shadowColor": "#FF000000",
    "shadowOpacity": 1.0,
    "shadowBlur": 0.5,
    "shadowDistance": 0.0,
    "shadowAngle": 45.0,
    "opacity": 1.0,
    "anim": "none",
    "fadeIn": 0.0,
    "fadeOut": 0.0,
}

ALIGNMENTS = ("left", "center", "right")
ANIMATIONS = (
    "none", "fade", "popIn", "slideUp", "slideDown",
    "zoomIn", "bounce", "typewriter", "shake", "pulse",
)

#: Only what each preset changes; everything else comes from FIELD_DEFAULTS.
_SEED: list[dict[str, Any]] = [
    {"name": "Bold Meme", "font": "Anton", "fontSize": 52, "strokeWidth": 6, "anim": "popIn"},
    {"name": "Subtitle", "font": "Montserrat", "fontSize": 40, "bgEnabled": True,
     "bgColor": "#B3000000", "anim": "fade"},
    {"name": "Impact", "font": "Archivo Black", "fontSize": 50, "strokeWidth": 5, "anim": "zoomIn"},
    {"name": "Neon Pop", "font": "Bebas Neue", "fontSize": 50, "color": "#FF0E9E6E",
     "strokeWidth": 4, "strokeColor": "#FFFFFFFF", "shadow": True,
     "shadowColor": "#FF0E9E6E", "shadowBlur": 0.8, "anim": "bounce"},
    {"name": "Sunshine", "font": "Poppins", "color": "#FF17131F", "bgEnabled": True,
     "bgColor": "#FFFFC400", "anim": "slideUp"},
    {"name": "Marker", "font": "Permanent Marker", "fontSize": 46, "strokeWidth": 3, "anim": "shake"},
    {"name": "Retro", "font": "Lobster", "fontSize": 46, "color": "#FFFFC400",
     "strokeWidth": 3, "strokeColor": "#FF3A2600", "anim": "slideDown"},
    {"name": "Headline", "font": "Oswald", "bgEnabled": True, "bgColor": "#FF0E9E6E",
     "anim": "typewriter"},
    {"name": "Handwrite", "font": "Caveat", "fontSize": 52, "strokeWidth": 3, "anim": "fade"},
    {"name": "Party", "font": "Shrikhand", "fontSize": 46, "color": "#FF12B886",
     "strokeWidth": 3, "strokeColor": "#FFFFFFFF", "anim": "pulse"},
    {"name": "Clean", "font": "Inter", "fontSize": 42, "shadow": True,
     "shadowOpacity": 0.8, "shadowBlur": 0.4},
    {"name": "Boxed", "font": "Montserrat", "fontSize": 42, "color": "#FF000000",
     "bgEnabled": True, "bgColor": "#FFFFFFFF", "anim": "popIn"},
    {"name": "Fire", "font": "Anton", "fontSize": 52, "color": "#FFFFC400",
     "strokeWidth": 5, "strokeColor": "#FFC2272D", "anim": "zoomIn"},
    {"name": "Mint", "font": "Poppins", "bgEnabled": True, "bgColor": "#FF12B76A",
     "anim": "slideUp"},
    {"name": "Ocean", "font": "Oswald", "bgEnabled": True, "bgColor": "#FF2D7FF9",
     "anim": "slideDown"},
    {"name": "Comic", "font": "Bungee", "fontSize": 46, "strokeWidth": 5, "anim": "bounce"},
    {"name": "Script", "font": "Pacifico", "fontSize": 48, "strokeWidth": 3, "anim": "fade"},
    {"name": "Gold", "font": "Playfair Display", "fontSize": 46, "color": "#FFD89A3C",
     "strokeWidth": 2, "strokeColor": "#FF3A2600", "anim": "slideUp"},
]


def _complete(p: dict[str, Any]) -> dict[str, Any]:
    """One preset with every field present.

    The app fills gaps too, but sending a complete record means the admin sees
    what a preset actually does rather than a handful of keys and a shrug.
    """
    out = {"name": str(p.get("name") or "Preset").strip() or "Preset"}
    for key, default in FIELD_DEFAULTS.items():
        out[key] = p.get(key, default)
    return out


def defaults() -> list[dict[str, Any]]:
    return [_complete(p) for p in _SEED]


def validate(raw: Any) -> list[dict[str, Any]]:
    """Check a submitted preset list, or say exactly what is wrong with it.

    Raises ValueError. The admin screen is the only writer and a bad list would
    reach every customer's editor, so this is strict about the things that
    cannot be defaulted away: the shape, the names, and the two enums.
    """
    if not isinstance(raw, list):
        raise ValueError("presets must be a list")
    if not raw:
        raise ValueError("there must be at least one preset")
    if len(raw) > 60:
        raise ValueError("that is more presets than anyone will scroll through (max 60)")

    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for i, p in enumerate(raw):
        where = f"preset {i + 1}"
        if not isinstance(p, dict):
            raise ValueError(f"{where} is not an object")
        name = str(p.get("name") or "").strip()
        if not name:
            raise ValueError(f"{where} has no name")
        if name.lower() in seen:
            raise ValueError(f"two presets are both called {name!r}")
        seen.add(name.lower())
        if p.get("align", "center") not in ALIGNMENTS:
            raise ValueError(f"{name}: align must be one of {', '.join(ALIGNMENTS)}")
        if p.get("anim", "none") not in ANIMATIONS:
            raise ValueError(f"{name}: anim must be one of {', '.join(ANIMATIONS)}")
        for key in ("color", "strokeColor", "bgColor", "shadowColor"):
            v = p.get(key, FIELD_DEFAULTS[key])
            if not isinstance(v, str) or not _is_colour(v):
                raise ValueError(f"{name}: {key} must look like #AARRGGBB")
        for key in ("fontSize", "letterSpacing", "lineHeight", "strokeWidth",
                    "shadowOpacity", "shadowBlur", "shadowDistance", "shadowAngle",
                    "opacity", "fadeIn", "fadeOut"):
            v = p.get(key, FIELD_DEFAULTS[key])
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                raise ValueError(f"{name}: {key} must be a number")
        out.append(_complete({**p, "name": name}))
    return out


def _is_colour(v: str) -> bool:
    t = v.strip().lstrip("#")
    if len(t) not in (6, 8):
        return False
    try:
        int(t, 16)
    except ValueError:
        return False
    return True


def get(db: Session) -> list[dict[str, Any]]:
    """What the app should show. The defaults until an admin has saved a set."""
    row = db.get(AppSetting, CAPTION_PRESETS)
    if row is None:
        return defaults()
    stored = row.value.get("presets") if isinstance(row.value, dict) else None
    if not isinstance(stored, list) or not stored:
        return defaults()
    return [_complete(p) for p in stored if isinstance(p, dict)]


def put(db: Session, presets: list[dict[str, Any]]) -> list[dict[str, Any]]:
    clean = validate(presets)
    row = db.get(AppSetting, CAPTION_PRESETS)
    if row is None:
        row = AppSetting(key=CAPTION_PRESETS, value={"presets": clean})
        db.add(row)
    else:
        row.value = {"presets": clean}
    db.commit()
    return clean
