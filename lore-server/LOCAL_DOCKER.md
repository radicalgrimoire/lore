# Local Docker trial

This manual-only workflow builds an image containing the `lore` CLI and a running `loreserver`.
It is intended for local experiments, not production deployment.

From the repository root, build and start the server:

```sh
docker compose -f lore-server/compose-trial.yaml up --build --detach
```

The server is available on port `41337` over TCP (gRPC) and UDP (QUIC), with its health endpoint at `http://127.0.0.1:41339/health_check`.

The named volume `lore-local-data` is mounted at `/lore-data`. Both the immutable and mutable local stores write there, so pushed repository data survives container recreation. Remove the volume only when you intentionally want to discard that data:

```sh
docker compose -f lore-server/compose-trial.yaml down --volumes
```

The image runs as the unprivileged `lore:lore` account. Both `lore` and `loreserver` are installed in `/usr/local/bin`. Run the CLI inside the started container with:

```sh
docker compose -f lore-server/compose-trial.yaml exec lore-server lore --help
```

## Published image

The **Publish local Lore image** GitHub Actions workflow runs manually and publishes the image to GitHub Container Registry. It verifies both binaries, the `lore:lore` account, and write access to `/lore-data` before publishing.

It reads `loreserver --version` from the built image and publishes the numeric development version as the only tag. For example, `loreserver 0.8.7-nightly` publishes `ghcr.io/<repository-owner>/lore-local:0.8.7`.

See service logs or verify readiness with:

```sh
docker compose -f lore-server/compose-trial.yaml logs --follow lore-server
curl --fail http://127.0.0.1:41339/health_check
```