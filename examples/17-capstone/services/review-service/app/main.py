"""review-service — a §17 capstone data product: product reviews/ratings.

A minimal REST data product, added (and backed out) as a Phase A demonstration
of the add-a-data-product-to-the-mesh workflow: stand up the product, publish
its OpenAPI contract to Apicurio, ingest it into OpenMetadata with lineage to
the product (inventory) domain, and show the ways to retrieve the data and
discover its metadata.

Endpoints:
  GET  /health           — liveness (process is up)
  GET  /healthz          — readiness (Postgres reachable)
  GET  /version          — service + version (used by discovery)
  POST /reviews          — create a review
  GET  /reviews          — list reviews (optional ?sku= filter)
  GET  /reviews/{id}     — fetch one review

Storage: the service's own `reviews` Postgres schema (per-service ownership,
CAP-003). Seeded with a few rows at startup so the catalog and lineage demo
has data to show immediately.
"""

from __future__ import annotations

import uuid

from fastapi import FastAPI, HTTPException, status
from sqlalchemy import select

from app.config import settings
from app.db import SessionLocal, check_db, dispose, init_schema, seed_if_empty
from app.models import Review
from app.schemas import ReviewCreate, ReviewResponse
from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: ensure the `reviews` schema + table exist, then seed demo rows.
    await init_schema()
    await seed_if_empty()
    yield
    # Shutdown: dispose the connection pool cleanly (Managed Lifecycle pattern).
    await dispose()


app = FastAPI(
    title="review-service",
    version="1.0.0",
    description="review-service data product for the §17 capstone data mesh: product reviews/ratings.",
    lifespan=lifespan,
)


@app.get("/health", tags=["ops"])
async def health() -> dict[str, str]:
    """Liveness: the process is running. Always 200 if we can respond."""
    return {"status": "ok", "service": settings.service_name}


@app.get("/healthz", tags=["ops"])
async def healthz() -> dict[str, str]:
    """Readiness: we can serve traffic (Postgres reachable)."""
    if not await check_db():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unreachable",
        )
    return {"status": "ready", "service": settings.service_name}


@app.get("/version", tags=["ops"])
async def version() -> dict[str, str]:
    """Service identity + version (read by the discovery publish step)."""
    return {"service": settings.service_name, "version": app.version}


@app.post(
    "/reviews",
    response_model=ReviewResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["reviews"],
)
async def create_review(payload: ReviewCreate) -> Review:
    review = Review(
        id=str(uuid.uuid4()),
        sku=payload.sku,
        rating=payload.rating,
        reviewer=payload.reviewer,
        comment=payload.comment,
    )
    async with SessionLocal() as session:
        session.add(review)
        await session.commit()
        await session.refresh(review)
    return review


@app.get("/reviews", response_model=list[ReviewResponse], tags=["reviews"])
async def list_reviews(sku: str | None = None, limit: int = 100) -> list[Review]:
    """List reviews, newest first. Filter by product `sku` when provided."""
    stmt = select(Review).order_by(Review.created_at.desc()).limit(limit)
    if sku:
        stmt = select(Review).where(Review.sku == sku).order_by(
            Review.created_at.desc()
        ).limit(limit)
    async with SessionLocal() as session:
        result = await session.execute(stmt)
        return list(result.scalars().all())


@app.get("/reviews/{review_id}", response_model=ReviewResponse, tags=["reviews"])
async def get_review(review_id: str) -> Review:
    async with SessionLocal() as session:
        review = await session.get(Review, review_id)
    if review is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="review not found"
        )
    return review
