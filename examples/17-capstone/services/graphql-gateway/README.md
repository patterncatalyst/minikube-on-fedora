# graphql-gateway

A §17 capstone data product (read layer). Stateless — owns no data; it
federates reads across services by calling them:

- `order(id)` → order-service over **REST**
- `Order.stock` → inventory-service over **gRPC** (`CheckStock`)

GraphQL stitches both into one response shaped by the client's query. This
is federation by **gateway orchestration**; true subgraph federation (each
service exposing its own subgraph, composed into a supergraph) is the
production-scale pattern — see the §17 prose (CAP-016).

## Build + deploy

```bash
# from examples/17-capstone/
./scripts/gen-protos.sh                       # if stubs not generated yet
./scripts/build-image.sh services/graphql-gateway graphql-gateway v1
helm upgrade --install graphql-gateway charts/capstone/charts/graphql-gateway -n capstone
```

The image is built with Docker Engine and loaded into the `mof-capstone` profile (bare name, `imagePullPolicy: Never`). Once deployed, the service is reachable on the host at `http://127.0.0.1:18099` through its published NodePort.

Then open `/graphql` in a browser for the GraphiQL UI, or run
`./demos/smoke-graphql.sh`.
