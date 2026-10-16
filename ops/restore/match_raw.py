"""Recover each clip's base_clip_path by matching picture content.

The public-API backup can't carry base_clip_path, and R2 upload timestamps are
useless for re-pairing (raws went up over hours in batches while every thumb was
generated inside one short window). What IS reliable: thumbs/{clip_id}.jpg was
cut from that clip's own raw, so fingerprinting frames against the thumbs
recovers the mapping.

Two passes: a coarse one over a handful of sampled frames, then a dense re-sample
of whatever stayed ambiguous, re-assigned optimally rather than greedily.

Measured on this catalog: the closest any two thumbs come to each other is
0.802, well under the 0.85 cut, so a true pairing has a wide margin to win by.

  python match_raw.py --pilot 5   # sanity-check the signal on a few raws
  python match_raw.py             # full run -> mapping.json
"""
import io
import json
import os
import subprocess
import sys
import tempfile

import boto3
import numpy as np
from PIL import Image
from scipy.optimize import linear_sum_assignment

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
COARSE_FRACTIONS = [0.0, 0.02, 0.1, 0.25, 0.5]
CUT = 0.85  # below this a pairing goes to the dense second pass


def sig(img):
    """32x32 mean-centred unit vector - tolerant of rescale and jpeg noise."""
    a = np.asarray(img.convert("L").resize((32, 32), Image.BILINEAR), dtype=np.float64).ravel()
    a -= a.mean()
    n = np.linalg.norm(a)
    return a / n if n else a


def keys(prefix, depth=None):
    out = []
    for pg in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=prefix):
        for o in pg.get("Contents", []):
            if depth is None or o["Key"].count("/") == depth:
                out.append(o["Key"])
    return out


def frames(path, times):
    out = []
    for t in times:
        r = subprocess.run(
            ["ffmpeg", "-v", "error", "-ss", f"{t:.2f}", "-i", path,
             "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"],
            capture_output=True, timeout=120)
        if r.returncode == 0 and r.stdout:
            try:
                out.append(sig(Image.open(io.BytesIO(r.stdout))))
            except Exception:
                pass
    return out


def dense_frames(path, step=0.5, cap=90):
    """Every `step` seconds in one decode pass - cheaper than seeking per frame."""
    with tempfile.TemporaryDirectory() as d:
        outdir = os.path.join(d, "f")
        os.makedirs(outdir)
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-vf", f"fps=1/{step},scale=160:-1",
             "-frames:v", str(cap), os.path.join(outdir, "%03d.png")],
            capture_output=True, timeout=600)
        out = []
        for f in sorted(os.listdir(outdir)):
            try:
                out.append(sig(Image.open(os.path.join(outdir, f))))
            except Exception:
                pass
        return out


def raw_sigs(key, dense=False):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "v.mp4")
        s3.download_file(BUCKET, key, path)
        if dense:
            return dense_frames(path)
        dur = 0.0
        try:
            dur = float(subprocess.run(
                ["ffprobe", "-v", "error", "-show_entries", "format=duration",
                 "-of", "default=nw=1:nk=1", path],
                capture_output=True, text=True, timeout=60).stdout.strip() or 0)
        except Exception:
            pass
        return frames(path, [f * dur if dur else f for f in COARSE_FRACTIONS])


thumbs = keys("thumbs/")
raws = keys("clips/", depth=2)
print(f"{len(thumbs)} thumbs / {len(raws)} raws", flush=True)

T, tids = [], []
for k in thumbs:
    body = s3.get_object(Bucket=BUCKET, Key=k)["Body"].read()
    T.append(sig(Image.open(io.BytesIO(body))))
    tids.append(k.split("/")[-1].rsplit(".", 1)[0])
T = np.array(T)

pilot = int(sys.argv[sys.argv.index("--pilot") + 1]) if "--pilot" in sys.argv else None

# -- pass 1: coarse ---------------------------------------------------------
scores = {}
for i, rk in enumerate(raws if pilot is None else raws[:pilot]):
    sigs = raw_sigs(rk)
    if not sigs:
        print(f"  !! no frames from {rk}", flush=True)
        continue
    best = (T @ np.array(sigs).T).max(axis=1)
    scores[rk] = best
    order = np.argsort(-best)
    print(f"[{i+1}] {rk.split('/')[-1][:34]:34s} top={best[order[0]]:.3f} "
          f"2nd={best[order[1]]:.3f} gap={best[order[0]]-best[order[1]]:.3f}", flush=True)

if pilot is not None:
    sys.exit(0)

rk_list = list(scores)
M = np.array([scores[k] for k in rk_list])  # raws x thumbs
rows, cols = linear_sum_assignment(-M)
mapping = {tids[c]: {"key": rk_list[r], "score": float(M[r, c])} for r, c in zip(rows, cols)}

# -- pass 2: dense re-sample for the ambiguous ones -------------------------
weak = {t: v for t, v in mapping.items() if v["score"] < CUT}
print(f"\n{len(weak)}/{len(mapping)} below {CUT} - re-sampling those densely", flush=True)
if weak:
    wt = list(weak)
    wk = [weak[t]["key"] for t in wt]
    TW = np.array([T[tids.index(t)] for t in wt])
    MW = np.zeros((len(wk), len(wt)))
    for i, rk in enumerate(wk):
        sigs = raw_sigs(rk, dense=True)
        if sigs:
            MW[i] = (TW @ np.array(sigs).T).max(axis=1)
        print(f"  [{i+1}/{len(wk)}] {rk.split('/')[-1][:32]:32s} best={MW[i].max():.3f}", flush=True)
    r2, c2 = linear_sum_assignment(-MW)
    for r, c in zip(r2, c2):
        mapping[wt[c]] = {"key": wk[r], "score": float(MW[r, c])}

json.dump(mapping, open("/opt/restore/mapping.json", "w"), indent=1)
ss = sorted(v["score"] for v in mapping.values())
print(f"\nwrote mapping.json: {len(mapping)} pairs | min={ss[0]:.3f} "
      f"p10={ss[len(ss)//10]:.3f} median={ss[len(ss)//2]:.3f} >=0.85: {sum(s >= 0.85 for s in ss)}/{len(ss)}")
