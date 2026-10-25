# auth.py
# Minimal API key protection for write endpoints (POST /telemetry,
# POST /victims). Read endpoints (GET) stay open since the app itself
# only reads data — only devices/scripts that WRITE data need the key.
#
# Set your real key as an environment variable before deploying anywhere
# beyond your own machine:
#   export TRITON_API_KEY="something-long-and-random"
# Falls back to a placeholder dev key if unset — fine for local testing,
# NOT fine to leave as-is anywhere reachable outside your own network.

import os
from fastapi import Header, HTTPException

API_KEY = os.environ.get("TRITON_API_KEY", "dev-key-change-me")


def verify_api_key(x_api_key: str = Header(...)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key header")
