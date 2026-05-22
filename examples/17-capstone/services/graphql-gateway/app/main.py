"""graphql-gateway — the §17 capstone's federated read layer.

r24 scope: a single Strawberry GraphQL endpoint that composes reads across
services — order-service (REST) and inventory-service (gRPC) — into one
queryable graph. The gateway is stateless; it owns no data and no schema.

This models federation by *gateway orchestration* (one gateway calls the
services). True subgraph federation — where each service exposes its own
GraphQL subgraph and a gateway composes them via a supergraph — is the
production-scale pattern; see §17 prose for when you'd use it (CAP-016).

Endpoints:
  GET  /health   — liveness (process is up)
  GET  /healthz  — readiness (process can serve; gateway has no datastore)
  GET  /sdl      — the GraphQL schema as SDL (the gateway's discovery contract)
  /graphql       — the GraphQL endpoint (GraphiQL UI in a browser)
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
from strawberry.fastapi import GraphQLRouter

from app.config import settings
from app.schema import schema

app = FastAPI(
    title="graphql-gateway",
    version="0.1.0",
    description="Federated GraphQL read layer for the §17 capstone (gateway orchestration).",
)

graphql_app = GraphQLRouter(schema)
app.include_router(graphql_app, prefix="/graphql")


@app.get("/health", tags=["ops"])
async def health() -> dict[str, str]:
    """Liveness: the process is running."""
    return {"status": "ok", "service": settings.service_name}


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    """Readiness: the gateway can serve GraphQL.

    Deliberately does NOT probe downstream services — readiness should
    reflect 'can I accept traffic', not 'are my dependencies healthy'.
    Coupling readiness to downstreams causes cascading unavailability;
    downstream failures surface per-field at query time instead.
    """
    return {"status": "ready", "service": settings.service_name}


@app.get("/sdl", response_class=PlainTextResponse, tags=["ops"])
async def sdl() -> str:
    """The gateway's GraphQL schema as SDL — its **discovery contract**.

    This is what gets published to Apicurio (as a GRAPHQL artifact) so the
    schema is registered, versioned, and discoverable. Unlike the Avro event
    contract, it's not on any runtime path — nothing here fails if the
    registry is absent; it exists to be discovered (and later ingested into
    the data catalog).
    """
    return schema.as_str()
