"""Configuration for payment-service, sourced from environment variables.

In-cluster, the Postgres connection comes from the CloudNativePG-generated
Secret (`capstone-postgres-app`), surfaced as env vars by the helm subchart.
Locally, the defaults allow running against a port-forwarded Postgres.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    # Service identity
    service_name: str = "payment-service"
    service_schema: str = "payments"

    # Postgres connection. In-cluster these come from the CNPG app Secret.
    pg_host: str = "127.0.0.1"
    pg_port: int = 5432
    pg_user: str = "capstone_app"
    pg_password: str = "changeme"
    pg_database: str = "capstone"

    # Server
    host: str = "0.0.0.0"
    port: int = 8080

    @property
    def database_url(self) -> str:
        """Async SQLAlchemy URL using the asyncpg driver."""
        return (
            f"postgresql+asyncpg://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_database}"
        )


settings = Settings()
