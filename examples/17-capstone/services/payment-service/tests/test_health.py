"""Liveness endpoint test for payment-service — no DB required.

Readiness (/healthz) is exercised in-cluster by the smoke test, since it
needs a real Postgres. This unit test just confirms the app wires up and
/health answers.
"""

from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient


@pytest.mark.asyncio
async def test_health_ok():
    # Import inside the test so collection doesn't trigger the DB lifespan.
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "payment-service"
