"""Derives a clip's preview and poster from the raw file a creator uploaded.

Why this exists at all: the API signs URLs for `previews/{id}.mp4` and
`thumbs/{id}.jpg` from the clip's id alone, so a clip always *looks* like it has
media. Nothing made those objects, so a creator upload reached the catalogue as
a blank tile whose player showed nothing and whose editor refused to open — and
a credit was spent getting there.

Why on the server rather than on the creator's phone, which already has an
encoder: only the server can *guarantee* the invariant. A phone that dies
mid-upload, a web uploader added later, a bulk import — each would reproduce
the same broken state. Here there is one implementation, whatever the upload
path, and approval can refuse a clip whose media is not ready.

Why a polled claim rather than a queue: Postgres already runs in this stack and
`FOR UPDATE SKIP LOCKED` is exactly a work queue. Several workers can run side
by side without ever taking the same clip, and there is no broker to pay for,
operate or lose.
"""
from __future__ import annotations

import logging
import os
import shlex
import subprocess
import tempfile
import time
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, text

from app.db.session import SessionLocal
from app.models import Clip
from app.services.storage import storage

log = logging.getLogger("derive")

# A preview is for browsing, not for editing: short edge 720, no audio, and
# faststart so it begins playing before it has finished downloading.
PREVIEW_SHORT_EDGE = 720
PREVIEW_CRF = "28"

POLL_SECONDS = 5
# A worker that dies mid-job leaves its claim behind; after this another worker
# may take the clip. Longer than any sane encode, short enough to self-heal.
CLAIM_TIMEOUT = timedelta(minutes=20)
MAX_ATTEMPTS = 3


def preview_key(clip_id: uuid.UUID) -> str:
    return f"previews/{clip_id}.mp4"


def thumb_key(clip_id: uuid.UUID) -> str:
    return f"thumbs/{clip_id}.jpg"


def _run(args: list[str], timeout: int = 900) -> subprocess.CompletedProcess:
    log.debug("run %s", shlex.join(args))
    return subprocess.run(args, capture_output=True, timeout=timeout)


def probe(path: str) -> dict:
    """The clip's real duration and frame size.

    What the uploader claimed is not evidence: the form lets a creator type any
    duration, and the catalogue shows it. Reading it off the file keeps the
    listing honest.
    """
    out = _run([
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height:format=duration",
        "-of", "default=noprint_wrappers=1:nokey=0", path,
    ], timeout=120)
    vals: dict[str, str] = {}
    for line in out.stdout.decode(errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    w, h = int(vals.get("width") or 0), int(vals.get("height") or 0)
    try:
        dur = float(vals.get("duration") or 0)
    except ValueError:
        dur = 0.0
    return {"width": w, "height": h, "duration": dur}


def _aspect_label(w: int, h: int) -> str | None:
    if w <= 0 or h <= 0:
        return None
    r = w / h
    for label, value in (("9:16", 9 / 16), ("1:1", 1.0), ("4:5", 0.8), ("16:9", 16 / 9)):
        if abs(r - value) < 0.04:
            return label
    return None


def make_preview(src: str, dst: str) -> None:
    """720-short-edge, muted, faststart. Muted on purpose: browsing is silent,
    and dropping the audio track is the cheapest size win there is."""
    r = _run([
        "ffmpeg", "-y", "-i", src,
        "-vf", f"scale='if(gt(iw,ih),-2,{PREVIEW_SHORT_EDGE})':"
               f"'if(gt(iw,ih),{PREVIEW_SHORT_EDGE},-2)':flags=bicubic",
        "-an",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", PREVIEW_CRF,
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", dst,
    ])
    if r.returncode != 0 or not os.path.exists(dst):
        raise RuntimeError("preview encode failed: " + r.stderr.decode(errors="replace")[-400:])


def make_thumb(src: str, dst: str, at: float) -> None:
    """A frame from a little way in. The first frame of a clip is very often
    black or a fade, which makes for a catalogue of empty tiles."""
    r = _run([
        "ffmpeg", "-y", "-ss", f"{at:.2f}", "-i", src,
        "-frames:v", "1",
        "-vf", f"scale='if(gt(iw,ih),-2,{PREVIEW_SHORT_EDGE})':"
               f"'if(gt(iw,ih),{PREVIEW_SHORT_EDGE},-2)'",
        "-q:v", "4", dst,
    ], timeout=180)
    if r.returncode != 0 or not os.path.exists(dst):
        raise RuntimeError("thumb grab failed: " + r.stderr.decode(errors="replace")[-400:])


def claim(db) -> Clip | None:
    """Take one clip that needs media, atomically.

    SKIP LOCKED is what lets a second worker start without any coordination:
    it walks past rows another transaction is holding instead of waiting.
    """
    stale = datetime.now(timezone.utc) - CLAIM_TIMEOUT
    row = db.execute(text("""
        SELECT id FROM clips
         WHERE base_clip_path IS NOT NULL
           AND media_status = 'pending'
           AND media_attempts < :max_attempts
           AND (media_claimed_at IS NULL OR media_claimed_at < :stale)
         ORDER BY created_at
         FOR UPDATE SKIP LOCKED
         LIMIT 1
    """), {"stale": stale, "max_attempts": MAX_ATTEMPTS}).first()
    if row is None:
        return None
    clip = db.get(Clip, row[0])
    clip.media_claimed_at = datetime.now(timezone.utc)
    clip.media_attempts = (clip.media_attempts or 0) + 1
    db.commit()
    db.refresh(clip)
    return clip


def derive(clip: Clip, db) -> None:
    """Make both files and record what the clip actually is."""
    with tempfile.TemporaryDirectory(prefix="derive-") as tmp:
        raw = os.path.join(tmp, "raw.mp4")
        with open(raw, "wb") as f:
            f.write(storage.get_bytes(clip.base_clip_path))

        meta = probe(raw)
        if meta["duration"] <= 0:
            raise RuntimeError("not a readable video (no duration)")

        prev = os.path.join(tmp, "preview.mp4")
        make_preview(raw, prev)
        thumb = os.path.join(tmp, "thumb.jpg")
        make_thumb(raw, thumb, at=min(1.0, meta["duration"] / 4))

        with open(prev, "rb") as f:
            storage.put_bytes(preview_key(clip.id), f.read(), "video/mp4")
        with open(thumb, "rb") as f:
            storage.put_bytes(thumb_key(clip.id), f.read(), "image/jpeg")

        # correct what the uploader claimed
        clip.duration_sec = int(round(meta["duration"]))
        short = min(meta["width"], meta["height"])
        if short:
            clip.resolution = "1080p" if short >= 1080 else ("720p" if short >= 720 else f"{short}p")
        label = _aspect_label(meta["width"], meta["height"])
        if label:
            clip.aspect_ratio = label
        clip.media_status = "ready"
        clip.media_error = None
        db.commit()
        log.info("clip %s ready: %ss %sx%s", clip.id, clip.duration_sec,
                 meta["width"], meta["height"])


def process_one(db) -> bool:
    """One unit of work. Returns False when there was nothing to do."""
    clip = claim(db)
    if clip is None:
        return False
    try:
        derive(clip, db)
    except Exception as e:  # noqa: BLE001 - the reason is stored, not swallowed
        db.rollback()
        clip = db.get(Clip, clip.id)
        clip.media_error = str(e)[:400]
        # Out of attempts: stop retrying and let an admin see why. Leaving it
        # pending forever would keep a dead clip in the queue for good.
        clip.media_status = "failed" if clip.media_attempts >= MAX_ATTEMPTS else "pending"
        clip.media_claimed_at = None
        db.commit()
        log.warning("clip %s attempt %s failed: %s", clip.id, clip.media_attempts, e)
    return True


def main() -> None:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    log.info("derive worker up")
    while True:
        did = False
        try:
            with SessionLocal() as db:
                did = process_one(db)
        except Exception:  # a dropped database connection must not end the worker
            log.exception("worker loop error")
            time.sleep(POLL_SECONDS)
        if not did:
            time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
