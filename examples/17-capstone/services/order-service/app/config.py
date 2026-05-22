"""Configuration for order-service, sourced from environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    service_name: str = "order-service"
    service_schema: str = "orders"

    # API contract version (r26). Selects which contract this instance serves;
    # the value is reported by GET /version and gates the v2-only response
    # fields. v1 and v2 run the SAME image, differing only by this env var and
    # their `version` pod label — the Istio canary shifts traffic between the
    # two subsets. In production v1/v2 would be distinct image tags from
    # distinct commits; the env toggle keeps the demo's focus on the traffic
    # split, not an image-build pipeline. The Istio mechanism is identical.
    api_version: str = "v1"

    pg_host: str = "127.0.0.1"
    pg_port: int = 5432
    pg_user: str = "capstone_app"
    pg_password: str = "changeme"
    pg_database: str = "capstone"

    host: str = "0.0.0.0"
    port: int = 8080

    inventory_grpc_addr: str = "inventory-service:50051"

    # Kafka (r25). order-service publishes order.placed events here.
    kafka_bootstrap: str = "capstone-kafka-kafka-bootstrap:9092"
    kafka_order_topic: str = "order-placed"

    # Apicurio schema registry (r25b). order.placed is registered + serialized
    # as Avro against this registry (Confluent-compatible ccompat API).
    # Subject follows the Confluent TopicNameStrategy: "<topic>-value".
    apicurio_url: str = "http://apicurio:8080"
    kafka_order_subject: str = "order-placed-value"

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+asyncpg://{self.pg_user}:{self.pg_password}"
            f"@{self.pg_host}:{self.pg_port}/{self.pg_database}"
        )


settings = Settings()
