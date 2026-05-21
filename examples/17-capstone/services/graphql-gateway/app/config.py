"""Configuration for graphql-gateway.

The gateway is stateless — it owns no data. It federates reads by calling
the existing services: order-service over REST, inventory-service over gRPC.
Endpoints come from env (the helm chart injects in-cluster Service names);
defaults target port-forwards for local runs.
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="", case_sensitive=False)

    service_name: str = "graphql-gateway"

    # Downstream services this gateway orchestrates.
    order_rest_url: str = "http://order-service"        # REST (port 80 in-cluster)
    inventory_grpc_addr: str = "inventory-service:50051"  # gRPC

    host: str = "0.0.0.0"
    port: int = 8080


settings = Settings()
