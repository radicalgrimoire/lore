# 社内ローカルのubuntu(172.20.12.193)のLoreサーバーを更新した時のメモ

この手順は、`172.20.12.193` で稼働している Lore Server を、テスト済みの
Lore source revision へ更新するときに使います。この deployment は
`/datadrive2/lore/data/store` の local immutable/mutable store と、Entra ID を
使う `lore-auth-bridge` で構成されています。

release は `/home/mgs/lore` の clone で公開済み Lore Git tag から build
します。tag のない `develop` または nightly commit を deployment しません。
新しい Lore binary の受入確認が終わるまで、bridge は更新しません。

> [!WARNING]
> Lore は pre-1.0 です。新しい version の server が write を受け付けた後は、
> 更新前の store snapshot を restore せずに downgrade しないでください。
> 受入確認が完了するまで、client に repository の create、clone、push を
> 行わせないでください。

## 開始前の確認

- 保守作業の承認を取り、`mgs` として SSH 接続できることを確認します。
- tag 一覧を取得してから、deployment する最新の公開済み release tag を選択します。
   この手順の更新時点での最新 tag は `v0.9.0` です。
- `/home/mgs/lore` が Lore build に使う既存の Git clone であることを確認します。

- `lore` が Lore Server の systemd unit 名であることを確認します。bridge の
  実際の unit 名も確認します。この手順では `lore-auth` を仮の unit 名として
  使用します。

  ```bash
  sudo systemctl status lore
  sudo systemctl list-unit-files '*lore*' '*auth*'
  ```

- 現在の server config が local store path を使用していることを確認します。

  ```bash
  grep -A2 -E '^\[(immutable|mutable)_store\.local\]' \
    /datadrive2/lore/config/dev.toml
  ```

> [!IMPORTANT]
> この手順は local store 専用です。AWS immutable store の場合は、別途
> `contrib/aws-migrate-0.9.0` による migration が必要です。この手順で
> migration を代替することはできません。

## tag を checkout して build する

1. **server 上で target tag を fetch して checkout します。**

   build が公開済み tag と完全に一致するよう、working tree が clean であることを
   必須とします。detached checkout により、変更され得る branch からの deployment を
   防ぎます。

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

2. **server 上で tag を build します。**

   mounted Windows drive ではなく、server の Linux filesystem で build します。

   ```bash
   source "$HOME/.cargo/env"
   cd /home/mgs/lore
   cargo build --release -p lore-client --bin lore -p lore-server --bin loreserver
   target/release/lore --version
   target/release/loreserver --version
   ```

## deployment をバックアップする

4. **保守時間を開始し、service を停止します。**

   `lore-auth` は確認済みの bridge unit 名に置き換えます。両 service を停止して、
   backup 中の store write と管理用 SQLite write を防ぎます。

   ```bash
   export LORE_SERVICE=lore
   export BRIDGE_SERVICE=lore-auth
   sudo systemctl stop "$LORE_SERVICE"
   sudo systemctl stop "$BRIDGE_SERVICE"
   sudo systemctl is-active "$LORE_SERVICE" "$BRIDGE_SERVICE"
   ```

   続行する前に、両 unit が `inactive` と表示されなければなりません。

5. **timestamp を含む rollback snapshot を一つ作成します。**

   Lore store、bridge SQLite database、bridge signing key は一つの recovery set を
   構成します。作成した directory は application path の外に保持します。

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

## release を配置して起動する

6. **稼働中の binary を保存してから、新しい build を配置します。**

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

7. **bridge を起動してから Lore Server を起動します。**

   bridge を先に起動すると、`loreserver` が JWT verification と ReBAC
   synchronization を初期化するとき、JWKS と gRPC endpoint が利用可能です。

   ```bash
   sudo systemctl start "$BRIDGE_SERVICE"
   curl -fk https://172.20.12.193:8080/healthz
   curl -fk https://172.20.12.193:8080/.well-known/jwks.json
   sudo systemctl start "$LORE_SERVICE"
   sudo systemctl status "$BRIDGE_SERVICE" "$LORE_SERVICE" --no-pager
   sudo journalctl -u "$LORE_SERVICE" -n 100 --no-pager
   ```

## 更新を確認する

8. **Entra user で受入確認を実行します。**

   administrator 用ではない既存の test repository と、`writer` を付与した user を
   使用します。login、既存 repository の read、write、repository create による
   ReBAC synchronization を確認します。権限を持たない user が拒否されることも
   確認します。

   ```powershell
   lore auth login lore://172.20.12.193:41337
   lore clone lore://172.20.12.193:41337/<existing-repository> <empty-directory>
   ```

   ```bash
   /home/mgs/lore-auth/bin/lore-authctl \
     --config /home/mgs/lore-auth/lore-auth.yaml \
     check <user-email> <existing-repository> write
   ```

   clone から小さな commit を作成して push します。続けて、認証済み Lore CLI で
   使い捨て repository を作成し、`lore-authctl repo list` に現れることを確認します。

> [!NOTE]
> Lore 0.9.0 は client credential を `tokens.toml` から `tokenstore.toml` に
> 移動しますが、自動 migration は行いません。以前の client で認証済みであっても、
> 新しい世代の client ごとに一度 `lore auth login` を実行してください。

## 更新をロールバックする

9. **受入確認が失敗した場合は更新前の snapshot を restore します。**

   deployment を公開しないまま作業します。新しい server が store へ write した
   可能性がある場合、以前の binary だけを restore してはいけません。

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

10. **作業結果を記録します。**

   release tag、source commit、binary version、保守開始・終了時刻、backup
   directory、受入確認結果、client の再 login に関する通知を記録します。

## 関連資料

- [Release notes](../release-notes.md)
- [Deploy a local Lore Server](../how-to/deploy-local-lore-server.md)
- [Lore Server configuration reference](../reference/lore-server-config.md)
- [English](update-172.20.12.193.md)