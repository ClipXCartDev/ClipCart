# ops

Everything needed to stand the server back up from nothing.

These scripts have now been lost twice - once with the old VPS's `/opt/restore`,
once when a scratchpad was cleaned - so they live in the repo. Nothing here
holds a secret: identity comes from `~/.oci/config`, the server's own secrets
are generated on the box by `stack.sh`, and the R2 / Google values are pasted
into `.env` by hand afterwards.

## oracle/ - getting a box out of the Always Free tier

    python oracle/launch_instance.py     # one grind, prints INSTANCE_ID on success
    bash   oracle/supervise.sh           # keeps the grind alive, logs to launch.log

Free A1 capacity in `ap-mumbai-1` is contended; expect a long wait. The ask is
rotated across 4/24, 2/12 and 1/6 OCPU and two boot-volume sizes, because
Oracle grants capacity per request and a smaller ask fits windows a larger one
never will. A1.Flex resizes afterwards with `instance update --shape-config`
plus a reboot, so landing small beats staying offline.

A Pay-As-You-Go account gets priority for this capacity and still keeps
4 OCPU / 24 GB / 200 GB free - that upgrade is the real fix for a long grind.

## server/ - turning a bare box into production

    bash server/go_live.sh <public-ip>

Runs three stages, each safe to re-run on its own:

1. `bootstrap.sh` - Oracle's Ubuntu image REJECTs everything past port 22 in
   iptables, *independently* of the cloud Security List. Both must be opened or
   the box looks dead on 80/443. Also Docker (arm64), ffmpeg, and 4 GB of swap.
2. `harden.sh` - `ccadmin` (sudo, human) and `deploy` (docker only, no sudo,
   used by GitHub Actions), key-only SSH, no root login, fail2ban. Hands
   `/opt/clipcart` to `deploy` while root is still available.
3. `stack.sh` - runs as `deploy` with no privilege at all. Clones the repo,
   generates the Postgres/JWT/storage secrets on the box, brings the compose
   stack up.

Then fill the `__PLACEHOLDER__` values in `/opt/clipcart/.env` (R2 and Google)
and set the `VPS_HOST` / `VPS_USER` / `VPS_SSH_KEY` GitHub secrets to turn on
auto-deploy.

## restore/ - rebuilding the catalog

The database does not survive a server loss, but the R2 media does. Run in
order, from inside the api container:

    restore_catalog.py    # 91 clips + 6 categories, original ids preserved
    match_raw.py          # recover base_clip_path by picture content
    validate_pairs.py     # independent duration cross-check
    apply_mapping.py --apply

`restore_catalog.py` keeps the original clip ids, so `thumbs/{id}.jpg` and
`previews/{id}.mp4` re-attach for free. `base_clip_path` is the one field the
public-API backup cannot carry, which is why it has to be recovered by
matching frames against the thumbnails.

### Locking the origin to Cloudflare

    bash server/lock_to_cloudflare.sh

Run after DNS is proxied. It is re-runnable and verifies container egress
before declaring success, because the obvious version of this rule silently
breaks image builds - see the comments in the script for why.
