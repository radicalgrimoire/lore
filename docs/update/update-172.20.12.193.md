# Update the 172.20.12.193 Lore Server

Use this procedure to move the Lore Server at `172.20.12.193` to a tested Lore
source revision. This deployment uses a local immutable and mutable store at
`/datadrive2/lore/data/store` and an Entra ID-backed `lore-auth-bridge`.

Build the release from a published Lore Git tag in the `/home/mgs/lore` clone.
Do not deploy an untagged `develop` or nightly commit. Keep the bridge version
unchanged until the new Lore binaries have passed the acceptance checks.

> [!WARNING]
> Lore is pre-1.0. Do not downgrade a server that has accepted writes from a new
> version without restoring the pre-update store snapshot. Keep clients from
> creating, cloning, or pushing repositories until the acceptance checks pass.

## Before you start

- Obtain maintenance approval and SSH access as `mgs`.
- Choose the latest published release tag after fetching the tag list. At the
   time this guide was updated, the latest tag was `v0.9.0`.
- Confirm that `/home/mgs/lore` is the existing Git clone used to build Lore.

- Confirm that `lore` is the Lore Server systemd unit name. Confirm the actual
  bridge unit name; this guide uses `lore-auth` as its placeholder.

  ```bash
  sudo systemctl status lore
  sudo systemctl list-unit-files '*lore*' '*auth*'
  ```

- Confirm that the current server config still uses the local store paths:

  ```bash
  grep -A2 -E '^\[(immutable|mutable)_store\.local\]' \
    /datadrive2/lore/config/dev.toml
  ```

> [!IMPORTANT]
> This is a local-store procedure. An AWS immutable store needs the separate
> `contrib/aws-migrate-0.9.0` migration and must not use these steps as a
> substitute.

## Check out and build the tagged release

1. **Fetch and check out the target tag on the server.**

   Require a clean working tree so the build is exactly the published tag. The
   detached checkout prevents an accidental deployment from a moving branch.

   ```bash
   ssh mgs@172.20.12.193
   cd /home/mgs/lore
   git fetch --tags origin
   git tag -l 'v*' --sort=-version:refname | head -n 10
   export LORE_TAG="$(git tag -l 'v*' --sort=-version:refname | head -n 1)"
   test -n "$LORE_TAG"
   git status --short
   git show-ref --verify --quiet "refs/tags/$LORE_TAG"
   git checkout --detach "$LORE_TAG"
   git describe --exact-match --tags HEAD
   git rev-parse HEAD
   ```

2. **Build the tag on the server.**

   Build on the server's Linux filesystem rather than a mounted Windows drive.

   ```bash
   source "$HOME/.cargo/env"
   cd /home/mgs/lore
   cargo build --release -p lore-client --bin lore -p lore-server --bin loreserver
   target/release/lore --version
   target/release/loreserver --version
   ```

## Back up the deployment

4. **Start the maintenance window and stop the services.**

   Replace `lore-auth` with the confirmed bridge unit name. Stopping both
   services prevents store writes and administrative SQLite writes while their
   backups are made.

   ```bash
   export LORE_SERVICE=lore
   export BRIDGE_SERVICE=lore-auth
   sudo systemctl stop "$LORE_SERVICE"
   sudo systemctl stop "$BRIDGE_SERVICE"
   sudo systemctl is-active "$LORE_SERVICE" "$BRIDGE_SERVICE"
   ```

   Both units must report `inactive` before continuing.

5. **Create one timestamped rollback snapshot.**

   The Lore store, bridge SQLite database, and bridge signing keys form one
   recovery set. Retain the resulting directory outside the application paths.

   ```bash
   export BACKUP_ROOT=/datadrive2/lore-backups
   export BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%dT%H%M%SZ)-pre-$LORE_TAG"
   sudo install -d -m 0700 "$BACKUP_DIR"
   sudo rsync -aHAX --numeric-ids /datadrive2/lore/data/store/ "$BACKUP_DIR/store/"
   sudo rsync -aHAX --numeric-ids /datadrive2/lore/config/ "$BACKUP_DIR/lore-config/"
   sudo rsync -aHAX --numeric-ids /home/mgs/lore-auth/data/ "$BACKUP_DIR/bridge-data/"
   sudo rsync -aHAX --numeric-ids /home/mgs/lore-auth/keys/ "$BACKUP_DIR/bridge-keys/"
   sudo install -m 0600 /home/mgs/lore-auth/lore-auth.yaml "$BACKUP_DIR/lore-auth.yaml"
   sudo sha256sum /datadrive2/lore/bin/lore /datadrive2/lore/bin/loreserver \
     | sudo tee "$BACKUP_DIR/binaries.sha256"
   ```

## Install and start the release

6. **Preserve the active binaries and install the new build.**

   ```bash
   export RELEASE_DIR="/datadrive2/lore/releases/$(date +%Y%m%dT%H%M%SZ)-$LORE_TAG"
   sudo install -d -m 0750 "$RELEASE_DIR"
   sudo install -m 0755 /datadrive2/lore/bin/lore "$RELEASE_DIR/lore.previous"
   sudo install -m 0755 /datadrive2/lore/bin/loreserver "$RELEASE_DIR/loreserver.previous"
   sudo install -m 0755 /home/mgs/lore/target/release/lore /datadrive2/lore/bin/lore
   sudo install -m 0755 /home/mgs/lore/target/release/loreserver /datadrive2/lore/bin/loreserver
   /datadrive2/lore/bin/lore --version
   /datadrive2/lore/bin/loreserver --version
   ```

7. **Start the bridge, then Lore Server.**

   Starting the bridge first makes its JWKS and gRPC endpoint available while
   `loreserver` initializes JWT verification and ReBAC synchronization.

   ```bash
   sudo systemctl start "$BRIDGE_SERVICE"
   curl -fk https://172.20.12.193:8080/healthz
   curl -fk https://172.20.12.193:8080/.well-known/jwks.json
   sudo systemctl start "$LORE_SERVICE"
   sudo systemctl status "$BRIDGE_SERVICE" "$LORE_SERVICE" --no-pager
   sudo journalctl -u "$LORE_SERVICE" -n 100 --no-pager
   ```

## Check the update

8. **Run the acceptance checks with an Entra user.**

   Use an existing non-administrator test repository and a user granted
   `writer`. Confirm login, an existing repository read, a write, and ReBAC
   synchronization through a repository create. Also confirm an unauthorized
   user remains denied.

   ```powershell
   lore auth login lore://172.20.12.193:41337
   lore clone lore://172.20.12.193:41337/<existing-repository> <empty-directory>
   ```

   ```bash
   /home/mgs/lore-auth/bin/lore-authctl \
     --config /home/mgs/lore-auth/lore-auth.yaml \
     check <user-email> <existing-repository> write
   ```

   Complete a small commit and push from the clone. Then create a disposable
   repository with the authenticated Lore CLI and confirm it appears in
   `lore-authctl repo list`.

> [!NOTE]
> Lore 0.9.0 moves client credentials from `tokens.toml` to `tokenstore.toml`
> without migration. Each client using the new generation must run `lore auth
> login` once, even when it was authenticated with an earlier client.

## Roll back the update

9. **Restore the pre-update snapshot when an acceptance check fails.**

   Keep the deployment unavailable. Do not merely restore the prior binaries if
   the new server may have written to the store.

   ```bash
   sudo systemctl stop "$LORE_SERVICE"
   sudo systemctl stop "$BRIDGE_SERVICE"
   sudo install -m 0755 "$RELEASE_DIR/lore.previous" /datadrive2/lore/bin/lore
   sudo install -m 0755 "$RELEASE_DIR/loreserver.previous" /datadrive2/lore/bin/loreserver
   sudo rsync -aHAX --delete "$BACKUP_DIR/store/" /datadrive2/lore/data/store/
   sudo rsync -aHAX --delete "$BACKUP_DIR/lore-config/" /datadrive2/lore/config/
   sudo rsync -aHAX --delete "$BACKUP_DIR/bridge-data/" /home/mgs/lore-auth/data/
   sudo rsync -aHAX --delete "$BACKUP_DIR/bridge-keys/" /home/mgs/lore-auth/keys/
   sudo install -m 0600 "$BACKUP_DIR/lore-auth.yaml" /home/mgs/lore-auth/lore-auth.yaml
   sudo systemctl start "$BRIDGE_SERVICE"
   sudo systemctl start "$LORE_SERVICE"
   ```

10. **Record the outcome.**

   Record the release tag, source commit, binary versions, maintenance start
   and end times, backup directory, acceptance-check results, and any client
   re-login notices.

## See also

- [Release notes](../release-notes.md)
- [Deploy a local Lore Server](../how-to/deploy-local-lore-server.md)
- [Lore Server configuration reference](../reference/lore-server-config.md)