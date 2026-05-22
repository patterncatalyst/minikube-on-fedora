#!/usr/bin/env python3
"""get_token.py — print an OpenMetadata bearer token to stdout.

Run inside the ingestion Jobs (and reused conceptually by the smoke). Logs in
as the default admin over the in-cluster server API and prints the access
token, which the Job then injects into the ingestion workflow's
`workflowConfig.openMetadataServerConfig.securityConfig.jwtToken` (and the
lineage script uses as a Bearer header).

DECISION (CAP-023): authenticate by ADMIN LOGIN, not by retrieving the
ingestion-bot's stored JWT. Reading the bot's auth mechanism requires admin
credentials anyway (chicken-and-egg), so logging in as admin and using that
token directly is strictly simpler and fully self-contained — no extra secret,
no host-side token plumbing. The ingestion-bot path remains the production
alternative for unattended pipelines.

Stdlib only (urllib/json/base64) so it runs in the ingestion image with no
added dependency.

VERIFY-POINTS (OpenMetadata 1.12.8 basic-auth; confirm at build time):
  * The default install is basic auth with admin@open-metadata.org / admin
    (the credential the r27 deploy documented and the smoke uses).
  * Basic-auth login is POST /api/v1/users/login with the password
    base64-encoded in the body, returning {"accessToken": "..."}. If the
    install uses a different auth provider, this is the thing to change.
"""
import base64
import json
import os
import sys
import urllib.request

HOST = os.environ.get("OM_HOST", "http://openmetadata:8585")
EMAIL = os.environ.get("OM_ADMIN_EMAIL", "admin@open-metadata.org")
PASSWORD = os.environ.get("OM_ADMIN_PASSWORD", "admin")  # demo default (r27)


def main() -> int:
    body = json.dumps(
        {
            "email": EMAIL,
            # OM basic-auth expects the password base64-encoded in the payload.
            "password": base64.b64encode(PASSWORD.encode()).decode(),
        }
    ).encode()
    req = urllib.request.Request(
        f"{HOST}/api/v1/users/login",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            token = json.load(resp).get("accessToken")
    except Exception as exc:  # noqa: BLE001 — surface anything as a clear error
        sys.stderr.write(f"failed to obtain OpenMetadata token from {HOST}: {exc}\n")
        return 1
    if not token:
        sys.stderr.write("login succeeded but no accessToken in the response\n")
        return 1
    sys.stdout.write(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
