"""Cross-check match_raw.py's assignment using a signal it never looked at.

The matcher pairs on picture content alone. Duration is independent evidence:
a preview is cut from its own raw, so the two should agree closely. A pair that
matches on pixels but disagrees badly on length is the one to look at by hand.

  python validate_pairs.py
"""
import json
import subprocess

import boto3

ENV = dict(
    l.split("=", 1) for l in open("/opt/clipcart/.env").read().splitlines()
    if "=" in l and not l.startswith("#")
)
s3 = boto3.client(
    "s3",
    endpoint_url=f"https://{ENV['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
    aws_access_key_id=ENV["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=ENV["R2_SECRET_ACCESS_KEY"],
    region_name="auto",
)
BUCKET = ENV["R2_BUCKET"]
TOLERANCE = 1.5  # seconds; re-encodes drift a little, cuts drift a lot


def duration(key):
    """ffprobe straight off a presigned URL - no need to pull whole files."""
    url = s3.generate_presigned_url(
        "get_object", Params={"Bucket": BUCKET, "Key": key}, ExpiresIn=3600)
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", url],
            capture_output=True, text=True, timeout=120).stdout.strip()
        return float(out) if out else None
    except Exception:
        return None


mapping = json.load(open("/opt/restore/mapping.json"))
bad, unknown, ok = [], [], 0

for i, (cid, v) in enumerate(sorted(mapping.items()), 1):
    dp = duration(f"previews/{cid}.mp4")
    dr = duration(v["key"])
    if dp is None or dr is None:
        unknown.append((cid, v))
        state = "??"
    elif abs(dp - dr) <= TOLERANCE:
        ok += 1
        state = "ok"
    else:
        bad.append((cid, v, dp, dr))
        state = "MISMATCH"
    print(f"[{i}/{len(mapping)}] {cid[:8]} score={v['score']:.3f} "
          f"preview={dp if dp is None else round(dp, 1)}s "
          f"raw={dr if dr is None else round(dr, 1)}s  {state}", flush=True)

print(f"\nagree within {TOLERANCE}s: {ok}/{len(mapping)}")
print(f"could not probe        : {len(unknown)}")
print(f"DISAGREE               : {len(bad)}")
for cid, v, dp, dr in bad:
    print(f"  {cid}  score={v['score']:.3f}  preview={dp:.1f}s raw={dr:.1f}s  {v['key']}")
if bad:
    print("\nReview these by eye before running apply_mapping.py --apply.")
