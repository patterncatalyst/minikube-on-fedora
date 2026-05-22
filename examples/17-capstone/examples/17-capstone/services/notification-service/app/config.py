"""Configuration for notification-service.

notification-service is a Kafka-consumer-only data product: it reacts to
events from other services rather than serving synchronous domain calls. It
still owns the `notifications` Postgres schema (per-service ownership,
CAP-003) and keeps its REST surface for health + observability.
"""

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


settings = Settings()
