"""shipping-report CLI — the BatchJob/PeriodicJob runner's entrypoint.

Two subcommands:

  seed    — create the schema/table and insert demo shipment rows once.
  report  — read this partition's rows and write a CSV to the PVC mount.

`report` defaults its partition index from JOB_COMPLETION_INDEX so an
Indexed Job's Pod template can call it with no arguments at all; a plain
(non-indexed) Job or a CronJob run leaves JOB_COMPLETION_INDEX at 0 and
partition_count at 1, which selects every row — the correct behavior for
a single-Pod run.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

import typer

from app.config import settings
from app.db import connection, ensure_schema, partition, seed as seed_rows

app = typer.Typer(add_completion=False, help="shipping-report batch runner")


@app.command()
def seed(count: int = settings.seed_row_count) -> None:
    """Create the schema/table and seed demo shipment rows (idempotent)."""
    with connection() as conn:
        ensure_schema(conn)
        inserted = seed_rows(conn, count)
    if inserted:
        typer.echo(f"seeded {inserted} shipment_events rows")
    else:
        typer.echo("shipment_events already has rows; seed is a no-op")


@app.command()
def report(
    partition_index: int = typer.Option(
        settings.job_completion_index, envvar="JOB_COMPLETION_INDEX"
    ),
    partition_count: int = typer.Option(
        settings.partition_count, envvar="PARTITION_COUNT"
    ),
    output_dir: str = typer.Option(settings.output_dir, envvar="OUTPUT_DIR"),
    tag: str = typer.Option(
        "",
        envvar="REPORT_TAG",
        help="Report filename suffix. Defaults to the partition index; a "
        "plain (non-indexed) Job sets this to its own Pod name instead, "
        "via the Downward API, so concurrent redundant runs never collide.",
    ),
) -> None:
    """Write this partition's shipment rows to a CSV report on the PVC."""
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"report-{tag or partition_index}.csv"

    with connection() as conn:
        ensure_schema(conn)
        rows = list(partition(conn, partition_index, partition_count))

    with out_file.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["id", "destination_zone", "weight_kg", "shipped_at"])
        writer.writerows(rows)

    typer.echo(
        f"partition {partition_index}/{partition_count}: "
        f"wrote {len(rows)} rows to {out_file}"
    )


def main() -> None:
    app()


if __name__ == "__main__":
    sys.exit(main())
