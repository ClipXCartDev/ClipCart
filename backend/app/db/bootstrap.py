"""Brings an existing database up to the current model.

There is no migration tool here: the schema is created with `create_all`, which
makes tables that are missing but never alters one that already exists. So a
new column on a model that is already deployed simply does not appear, and the
first query that mentions it fails.

This closes that gap for the columns added since. Every statement is
conditional, so it is safe to run on every boot and on a fresh database alike.
If this project ever grows a real migration tool, this file is what it replaces.
"""
from __future__ import annotations

import logging

from sqlalchemy import inspect, text

from app.db.session import engine

log = logging.getLogger("bootstrap")

# column -> the DDL that adds it. Postgres only; SQLite (tests) always starts
# from a fresh create_all and so never needs them.
_CLIP_COLUMNS = {
    "media_status": "ALTER TABLE clips ADD COLUMN media_status VARCHAR(12) NOT NULL DEFAULT 'pending'",
    "media_error": "ALTER TABLE clips ADD COLUMN media_error VARCHAR(400)",
    "media_attempts": "ALTER TABLE clips ADD COLUMN media_attempts INTEGER NOT NULL DEFAULT 0",
    "media_claimed_at": "ALTER TABLE clips ADD COLUMN media_claimed_at TIMESTAMPTZ",
}

_INDEXES = (
    "CREATE INDEX IF NOT EXISTS ix_clips_media_status ON clips (media_status)",
)


def run() -> None:
    if engine.dialect.name != "postgresql":
        return
    insp = inspect(engine)
    if "clips" not in insp.get_table_names():
        return
    existing = {c["name"] for c in insp.get_columns("clips")}

    with engine.begin() as conn:
        added = []
        for name, ddl in _CLIP_COLUMNS.items():
            if name not in existing:
                conn.execute(text(ddl))
                added.append(name)
        for ddl in _INDEXES:
            conn.execute(text(ddl))

        if "media_status" in added:
            # Everything already approved and serving has its media: those files
            # were uploaded by the restore scripts, long before the worker
            # existed. Marking them pending would pull live clips out of the
            # catalogue and queue a pointless re-encode of all of them.
            n = conn.execute(text(
                "UPDATE clips SET media_status = 'ready' WHERE status = 'approved'"
            )).rowcount
            log.info("bootstrap: added %s, marked %s existing approved clips ready",
                     ", ".join(added), n)
        elif added:
            log.info("bootstrap: added %s", ", ".join(added))
