"""Write the recovered base_clip_path values into the database.

Dry by default: it prints what would change and touches nothing. Pass --apply
to commit, and --min-score to refuse pairings the matcher wasn't sure about.

  python apply_mapping.py                      # show the plan
  python apply_mapping.py --apply              # commit it
  python apply_mapping.py --apply --min-score 0.85
"""
import argparse
import json
import sys
import uuid

sys.path.insert(0, "/app")
import app.models  # noqa: F401  (register mappers)
from app.db.session import SessionLocal
from app.models.catalog import Clip

ap = argparse.ArgumentParser()
ap.add_argument("--apply", action="store_true", help="commit (default is a dry run)")
ap.add_argument("--min-score", type=float, default=0.0,
                help="skip pairings scoring below this")
ap.add_argument("--mapping", default="/opt/restore/mapping.json")
args = ap.parse_args()

mapping = json.load(open(args.mapping))
db = SessionLocal()

changed = skipped_low = missing = already = 0
for cid, v in sorted(mapping.items()):
    if v["score"] < args.min_score:
        print(f"SKIP  {cid[:8]} score={v['score']:.3f} below {args.min_score}")
        skipped_low += 1
        continue
    row = db.get(Clip, uuid.UUID(cid))
    if row is None:
        print(f"MISS  {cid[:8]} no such clip in db")
        missing += 1
        continue
    if row.base_clip_path == v["key"]:
        already += 1
        continue
    print(f"SET   {cid[:8]} score={v['score']:.3f}  {row.base_clip_path} -> {v['key']}")
    row.base_clip_path = v["key"]
    changed += 1

if args.apply:
    db.commit()
    print(f"\ncommitted: {changed} updated, {already} already correct, "
          f"{skipped_low} below threshold, {missing} missing")
else:
    db.rollback()
    print(f"\nDRY RUN - nothing written. would update {changed}, "
          f"{already} already correct, {skipped_low} below threshold, {missing} missing")
    print("re-run with --apply to commit")
