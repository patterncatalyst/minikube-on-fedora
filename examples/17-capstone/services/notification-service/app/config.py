"""Configuration for notification-service."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    service_name: str = "notification-service"
    service_schema: str = "notifications"

    pg_host: str = "127.0.0.1"
    pg_port: int = 5432
    pg_user: str = "capstone_app"
    pg_password: str = "changeme"
    pg_database: str = "capstone"

    host: str = "0.0.0.0"
    port: int = 8080

    # Kafka (r25). Consumes order.placed events.
    kafka_bootstrap: str = "capstone-kafka-kafka-bootstrap:9092"
    kafka_order_topic: str = "order-placed"
    kafka_group: str = "notification-service"

    # Apicurio schema registry (r25b). The consumer decodes Avro by fetching
    # the writer schema from this registry using the id embedded in each
    # message — it needs no local copy of the schema.
    apicurio_url: str = "http://apicurio:8080"

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+asyncpg://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_database}"
        )


settings = Settings()
