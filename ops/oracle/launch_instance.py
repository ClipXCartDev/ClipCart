"""Grind for an Always-Free Ampere box until Oracle gives one up.

Free A1 capacity in a given AD is handed out in short windows, so this keeps
asking. Two distinct failures need two cadences:
  - "Out of host capacity" is not throttling. Keep a steady, fairly fast poll.
  - 429 TooManyRequests IS throttling. Back off hard, or we cause it ourselves.

Oracle grants capacity per request, so the ask is rotated: a 1-OCPU request
fits windows a 4-OCPU one never will, and A1.Flex can be resized afterwards
(instance update --shape-config, then a reboot). Boot volume is varied for the
same reason - a 200 GB request and a default one are different asks.

Only genuine, permanent failures stop the loop. An overnight grind was once
lost to a transient network timeout that wasn't on an allow-list, so the test
is inverted: stop on auth/quota/parse errors, retry everything else.
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oci_cli import ENV, OCI, TENANCY, run

C = TENANCY
NAME = "clipcart-prod"
VCN_NAME = "clipcart-vcn"
SUBNET_NAME = "clipcart-public"
PUBKEY_PATH = r"D:\keys\oracle-clipcart\id_ed25519.pub"

ASKS = [({"ocpus": 4, "memoryInGBs": 24}, "200"),
        ({"ocpus": 2, "memoryInGBs": 12}, "200"),
        ({"ocpus": 1, "memoryInGBs": 6}, "200"),
        ({"ocpus": 4, "memoryInGBs": 24}, None),
        ({"ocpus": 1, "memoryInGBs": 6}, None)]

FATAL = ("NotAuthenticated", "NotAuthorized", "InvalidParameter",
         "LimitExceeded", "CannotParseRequest", "QuotaExceeded")


def existing():
    for i in run(["compute", "instance", "list", "--compartment-id", C, "--all"]) or []:
        if i["display-name"] == NAME and i["lifecycle-state"] in (
                "RUNNING", "PROVISIONING", "STARTING"):
            return i
    return None


def discover():
    """Resolve AD / subnet / image by name so no OCIDs live in this repo."""
    ad = (run(["iam", "availability-domain", "list", "--compartment-id", C]) or [])[0]["name"]
    vcn = next(v for v in run(["network", "vcn", "list", "--compartment-id", C]) or []
               if v["display-name"] == VCN_NAME)
    subnet = next(s for s in run(["network", "subnet", "list", "--compartment-id", C,
                                  "--vcn-id", vcn["id"]]) or []
                  if s["display-name"] == SUBNET_NAME)
    image = next(x for x in run(["compute", "image", "list", "--compartment-id", C,
                                 "--operating-system", "Canonical Ubuntu",
                                 "--operating-system-version", "24.04",
                                 "--shape", "VM.Standard.A1.Flex",
                                 "--sort-by", "TIMECREATED"]) or []
                 if "Minimal" not in x["display-name"])
    return ad, subnet["id"], image


inst = existing()
if inst:
    print("already exists:", inst["lifecycle-state"], inst["id"])
    sys.exit(0)

AD, SUBNET, IMG = discover()
print("ad     :", AD, flush=True)
print("image  :", IMG["display-name"], flush=True)

with open(PUBKEY_PATH) as f:
    pubkey = f.read().strip()


def launch_args(shape, boot):
    return [OCI, "compute", "instance", "launch",
            "--compartment-id", C,
            "--availability-domain", AD,
            "--display-name", NAME,
            "--shape", "VM.Standard.A1.Flex",
            "--shape-config", json.dumps(shape),
            "--image-id", IMG["id"],
            *(["--boot-volume-size-in-gbs", boot] if boot else []),
            "--subnet-id", SUBNET,
            "--assign-public-ip", "true",
            "--metadata", json.dumps({"ssh_authorized_keys": pubkey})]


env = {**os.environ, **ENV}
for attempt in range(1, 100001):
    shape, boot = ASKS[(attempt - 1) % len(ASKS)]
    tag = f"{shape['ocpus']}c/{shape['memoryInGBs']}g/{boot or 'def'}"
    p = subprocess.run(launch_args(shape, boot), capture_output=True, text=True, env=env)
    blob = (p.stdout or "") + (p.stderr or "")

    if p.returncode == 0 and '"id"' in blob:
        data = json.loads(blob[blob.find("{"):]).get("data", {})
        print(f"\nLAUNCHED on attempt {attempt} as {tag}")
        print("INSTANCE_ID=" + data["id"])
        sys.exit(0)

    # one may have slipped through even when the call reported an error
    inst = existing()
    if inst:
        print(f"\nfound running instance after attempt {attempt}: {inst['id']}")
        sys.exit(0)

    fatal = next((m for m in FATAL if m in blob), None)
    if fatal:
        print("FATAL:", fatal)
        print(blob[-1200:])
        sys.exit(1)

    why = ("Out of host capacity" if "Out of host capacity" in blob
           else "TooManyRequests" if "TooManyRequests" in blob
           else "transient: " + (blob.strip().splitlines() or ["unknown"])[0][:80])
    wait = 240 if "TooManyRequests" in blob else 120
    print(f"attempt {attempt} [{tag}]: {why} - retrying in {wait}s", flush=True)
    time.sleep(wait)
