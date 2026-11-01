"""Configuration for shipping-report, sourced from environment variables.

Mirrors the capstone services' own settings shape (service_schema, pg_*)
so the pattern reads the same way across the appendix, even though this
runner is a one-shot CLI rather than an HTTP service.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    # Postgres connection — the appendix's disposable patterns-postgres.
    pg_host: str = "patterns-postgres.patterns.svc.cluster.local"
    pg_port: int = 5432
    pg_user: str = "capstone_app"
    pg_password: str = "changeme"
    pg_database: str = "capstone"
    service_schema: str = "shipping"

    # Report output. /var/lib/shipping-reports is the mount point for the
    # shipping-reports PVC in both the BatchJob and PeriodicJob examples.
    output_dir: str = "/var/lib/shipping-reports"

    # Partitioning for the Indexed Job. Kubernetes sets JOB_COMPLETION_INDEX
    # automatically when completionMode: Indexed; partition_count must match
    # the Job's own `completions`.
    job_completion_index: int = 0
    partition_count: int = 1

    # How many demo rows `seed` inserts the first time the table is empty.
    seed_row_count: int = 300

    @property
    def dsn(self) -> str:
        return (
            f"host={self.pg_host} port={self.pg_port} "
            f"user={self.pg_user} password={self.pg_password} "
            f"dbname={self.pg_database}"
        )


settings = Settings()
