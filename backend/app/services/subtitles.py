"""Turn a subtitle file into caption layers the editor understands.

A creator arrives with an SRT next to their clip — that is how subtitles come
out of every transcription tool there is. Before this, the only way to get them
into a clip was to type each caption and set its two timestamps by hand, which
nobody does for a forty-caption file, so creator-authored captions effectively
did not happen.

This lives on the server rather than in each client because there are two
clients and one correct answer: the app and the web creator must produce the
same layers from the same file, and a parser is exactly the kind of thing that
drifts when it is written twice.

SRT and WebVTT are both accepted; they differ in the header, the comma versus
dot in timestamps, and the cue-id line, all of which this tolerates.
"""
from __future__ import annotations

import re

#: Where a caption sits and how it looks, matching SubtitleSegment's JSON keys.
#: Deliberately the plain defaults — the creator restyles them in the editor,
#: and a parser that invented a look would be overriding a decision that is
#: not its to make.
_DEFAULTS: dict = {
    "ff": None,      # fontFamily
    "c": 0xFFFFFFFF, # colour
    "fs": 44.0,      # fontSize, in video pixels
    "dx": 0.5,       # centred
    "dy": 0.82,      # low, where captions go
    "sc": 1.0,
    "rot": 0.0,
    "sw": 0.0,
    "scol": 0xFF000000,
    "bg": True,      # a box behind the text: captions over footage need it
    "bgc": 0x99000000,
    "al": 1,         # centre
    "hid": False,
    "fi": 0.0,
    "fo": 0.0,
    "an": 0,
    "ls": 0.0,
    "lh": 1.15,
    "bo": True,
    "it": False,
    "sh": False,
    "shc": 0xFF000000,
    "sho": 1.0,
    "shb": 0.5,
    "shd": 0.0,
    "sha": 45.0,
    "op": 1.0,
    "lk": False,
    "k": "text",
    "ln": 0,         # all on one line; the editor packs them onto one track
}

#: 00:01:02,500 or 00:01:02.500, and the hours are optional in some writers.
_TS = re.compile(r"(?:(\d+):)?(\d{1,2}):(\d{1,2})[,.](\d{1,3})")
_ARROW = re.compile(r"-->")

#: Inline styling SRT files carry that the editor has no place for. Stripped
#: rather than shown, because "<i>" in the middle of a caption is worse than
#: losing the italics.
_TAGS = re.compile(r"</?[a-zA-Z][^>]*>")

MAX_CAPTIONS = 400


class SubtitleError(ValueError):
    """Something about the file a person needs to be told, in their words."""


def _seconds(m: re.Match) -> float:
    h = int(m.group(1) or 0)
    mins, secs = int(m.group(2)), int(m.group(3))
    frac = m.group(4)
    # ",5" means half a second, not five milliseconds
    ms = int(frac.ljust(3, "0"))
    return h * 3600 + mins * 60 + secs + ms / 1000.0


def parse(text: str, *, duration: float | None = None) -> list[dict]:
    """Caption layers from [text], in time order.

    [duration] is the clip's length when it is known: captions past the end of
    the footage are dropped and one that overruns is trimmed, because a layer
    whose window lies outside the video renders nowhere and reads as the file
    having silently failed.
    """
    if not text or not text.strip():
        raise SubtitleError("That file is empty.")

    # BOM, and CRLF from Windows writers
    text = text.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")

    out: list[dict] = []
    for block in re.split(r"\n{2,}", text):
        lines = [l for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        # The cue-id line is optional and not always a number in VTT.
        timing_at = next((i for i, l in enumerate(lines) if _ARROW.search(l)), None)
        if timing_at is None:
            continue  # a WEBVTT header, a NOTE block, or junk between cues
        stamps = _TS.findall(lines[timing_at])
        if len(stamps) < 2:
            continue
        matches = list(_TS.finditer(lines[timing_at]))
        start, end = _seconds(matches[0]), _seconds(matches[1])

        body = " ".join(lines[timing_at + 1:]).strip()
        body = _TAGS.sub("", body)
        body = re.sub(r"\s+", " ", body).strip()
        if not body:
            continue

        if end <= start:
            # A zero-length or reversed cue renders nowhere; give it a readable
            # window rather than dropping what the creator wrote.
            end = start + 1.5
        if duration and duration > 0:
            if start >= duration:
                continue
            end = min(end, duration)
            if end <= start:
                continue

        out.append({**_DEFAULTS, "t": body, "s": round(start, 3), "e": round(end, 3), "z": float(len(out))})
        if len(out) >= MAX_CAPTIONS:
            break

    if not out:
        raise SubtitleError(
            "No captions found. The file should be an .srt or .vtt with lines like "
            "'00:00:01,000 --> 00:00:03,500' followed by the caption text."
        )
    out.sort(key=lambda c: c["s"])
    # z follows the sorted order so later captions sit above earlier ones
    for i, c in enumerate(out):
        c["z"] = float(i)
    return out
