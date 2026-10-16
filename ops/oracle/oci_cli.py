"""Thin wrapper around the OCI CLI.

Deliberately NOT named oci.py: that shadows the real `oci` SDK package for
anything running in the same directory, which is a nasty failure to debug.

Identity comes from ~/.oci/config, so no OCIDs or keys live in this repo.
"""
import configparser
import json
import os
import subprocess
import sys

OCI = os.environ.get(
    "OCI_CLI",
    r"C:\Users\91971\AppData\Roaming\Python\Python312\Scripts\oci.exe")

_cfg = configparser.ConfigParser()
_cfg.read(os.path.expanduser("~/.oci/config"))
PROFILE = os.environ.get("OCI_PROFILE", "DEFAULT")
TENANCY = _cfg[PROFILE]["tenancy"]
REGION = _cfg[PROFILE]["region"]

# The CLI prints key-permission warnings to stdout ahead of the JSON body, so
# the payload starts at the first brace rather than at the first byte.
ENV = {"PYTHONIOENCODING": "utf-8", "OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING": "True"}


def run(args, check=False):
    p = subprocess.run([OCI, *args], capture_output=True, text=True,
                       env={**os.environ, **ENV})
    blob = (p.stdout or "")
    i = blob.find("{")
    if i < 0:
        if check:
            raise RuntimeError((p.stderr or blob)[-800:])
        return None
    return json.loads(blob[i:]).get("data")


if __name__ == "__main__":
    print("tenancy:", TENANCY)
    print("region :", REGION)
    print("cli    :", OCI, "(found)" if os.path.exists(OCI) else "(MISSING)")
    sys.exit(0)
