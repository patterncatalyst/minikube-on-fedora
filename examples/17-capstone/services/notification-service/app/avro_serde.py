"""Transparent Avro serialization over a Confluent-compatible schema registry.

We talk to Apicurio through its Confluent-compatible API (`/apis/ccompat/v7`)
and implement the **Confluent Wire Format** ourselves so the registry
interaction is visible rather than hidden behind a serde library:

    byte 0:     magic byte 0x00
    bytes 1-4:  schema id, 4-byte big-endian
    bytes 5..:  Avro binary payload (fastavro schemaless)

This is Option A from the design discussion: minimal dependencies (fastavro +
httpx) and fully legible — the reader sees the schema get registered, the id
stamped into the bytes, and the consumer fetch the schema by id to decode.

Apicurio ccompat endpoints used:
    register:  POST {base}/apis/ccompat/v7/subjects/{subject}/versions
               body {"schema": "<avro json>", "schemaType": "AVRO"} -> {"id": N}
    by id:     GET  {base}/apis/ccompat/v7/schemas/ids/{id} -> {"schema": "<avro json>"}

A producer constructs the serde *with* a schema (to register + encode); a
consumer constructs it *without* one and only decodes (the writer schema is
fetched from the registry by the id embedded in each message).
"""

from __future__ import annotations

import io
import json
import struct

import fastavro
import httpx

_MAGIC = b"\x00"


class AvroRegistrySerde:
    def __init__(self, registry_url: str, subject: str, schema_dict: dict | None = None):
        self._base = registry_url.rstrip("/")
        self._subject = subject
        self._raw_schema = schema_dict
        # parse_schema may mutate its input, so hand it a deep copy
        self._parsed = (
            fastavro.parse_schema(json.loads(json.dumps(schema_dict)))
            if schema_dict is not None
            else None
        )
        self._schema_id: int | None = None
        self._reader_cache: dict[int, dict] = {}

    @property
    def schema_id(self) -> int | None:
        return self._schema_id

    # ---- producer side: register + encode ----

    async def register(self) -> int:
        """Register the schema under `{subject}` and cache the returned id."""
        if self._raw_schema is None:
            raise RuntimeError("no schema to register (consumer-only serde)")
        url = f"{self._base}/apis/ccompat/v7/subjects/{self._subject}/versions"
        body = {"schema": json.dumps(self._raw_schema), "schemaType": "AVRO"}
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(url, json=body)
            resp.raise_for_status()
            self._schema_id = int(resp.json()["id"])
        return self._schema_id

    def encode(self, record: dict) -> bytes:
        """Frame a record as magic + schema id + Avro payload."""
        if self._schema_id is None or self._parsed is None:
            raise RuntimeError("schema not registered; call register() first")
        buf = io.BytesIO()
        buf.write(_MAGIC)
        buf.write(struct.pack(">I", self._schema_id))
        fastavro.schemaless_writer(buf, self._parsed, record)
        return buf.getvalue()

    # ---- consumer side: decode (fetch writer schema by id) ----

    async def _schema_for_id(self, schema_id: int) -> dict:
        cached = self._reader_cache.get(schema_id)
        if cached is not None:
            return cached
        url = f"{self._base}/apis/ccompat/v7/schemas/ids/{schema_id}"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            schema = fastavro.parse_schema(json.loads(resp.json()["schema"]))
        self._reader_cache[schema_id] = schema
        return schema

    async def decode(self, data: bytes) -> dict:
        """Unframe and Avro-decode, fetching the writer schema by its id."""
        if len(data) < 5 or data[0:1] != _MAGIC:
            raise ValueError("not a Confluent-framed Avro message")
        schema_id = struct.unpack(">I", data[1:5])[0]
        schema = await self._schema_for_id(schema_id)
        return fastavro.schemaless_reader(io.BytesIO(data[5:]), schema)
