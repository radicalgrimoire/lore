#!/usr/bin/env bash
# Install a persistent Lore server from the local checkout.
#
# This script is intended for deployments where the Lore data must outlive a
# reboot and must not silently land in /tmp. It builds loreserver from the
# current checkout, configures a fixed data-root, writes a local config, and
# installs a systemd unit that starts the server with that config.
#
# Usage examples:
#   sudo ./scripts/install-persistent.sh --install-dir /usr/local/bin \
#       --config-dir /etc/lore/config --data-root /var/lib/lore-server \
#       --service-name lore-server --user mgs --group mgs
#
#   sudo ./scripts/install-persistent.sh --source-dir "$PWD" \
#       --data-root /datadrive2/lore-store --config-dir /etc/lore/config

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/lore/config"
CERT_DIR="/etc/lore/certs"
DATA_ROOT="/var/lib/lore-server"
SERVICE_NAME="lore-server"
RUN_AS_USER="mgs"
RUN_AS_GROUP="mgs"
ENV_NAME="local"

usage() {
    cat <<'EOF'
Install a persistent Lore server from the local checkout.

Usage:
    sudo ./scripts/install-persistent.sh [options]

Options:
  --source-dir <dir>        Lore checkout root to build from. Default: repo root
  --install-dir <dir>       Directory for the loreserver binary. Default: /usr/local/bin
  --config-dir <dir>        Directory for lore config files. Default: /etc/lore/config
  --cert-dir <dir>          Directory for certificates. Default: /etc/lore/certs
  --data-root <dir>         Persistent Lore data directory. Default: /var/lib/lore-server
  --service-name <name>     Systemd unit name. Default: lore-server
  --user <user>             Service account. Default: mgs
  --group <group>           Service group. Default: mgs
  --env <name>              Config env name. Default: local
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --cert-dir)
            CERT_DIR="$2"
            shift 2
            ;;
        --data-root)
            DATA_ROOT="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --user)
            RUN_AS_USER="$2"
            shift 2
            ;;
        --group)
            RUN_AS_GROUP="$2"
            shift 2
            ;;
        --env)
            ENV_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This script must be run as root (or with sudo)." >&2
    exit 1
fi

REPO_ROOT="$(cd "$SOURCE_DIR" && pwd)"
if [[ ! -d "$REPO_ROOT" ]]; then
    echo "Source directory not found: $REPO_ROOT" >&2
    exit 1
fi

if [[ ! -f "$REPO_ROOT/Cargo.toml" ]]; then
    echo "Source directory is not a Lore checkout (Cargo.toml not found): $REPO_ROOT" >&2
    exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
        echo "cargo is not installed, and curl is required to install Rust automatically." >&2
        echo "Install curl, then rerun this installer." >&2
        exit 1
    fi

    echo "cargo is not installed; installing the Rust stable toolchain for root."
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

    # rustup installs cargo under root's home; load it into this process before building.
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
    if ! command -v cargo >/dev/null 2>&1; then
        echo "Rust installation completed but cargo is still unavailable." >&2
        exit 1
    fi
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required but not installed." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$CERT_DIR" "$DATA_ROOT"

if ! id -u "$RUN_AS_USER" >/dev/null 2>&1; then
    echo "User '$RUN_AS_USER' does not exist. Create it first or pass --user/--group with an existing account." >&2
    exit 1
fi

chown -R "$RUN_AS_USER:$RUN_AS_GROUP" "$DATA_ROOT" "$CERT_DIR" "$CONFIG_DIR"

# Build the server from the local checkout.
BUILD_DIR="$REPO_ROOT/target/release"
cd "$REPO_ROOT"
cargo build --release --bin loreserver
install -m 0755 "$BUILD_DIR/loreserver" "$INSTALL_DIR/loreserver"

# Generate a self-signed cert if the user hasn't provided one.
CERT_FILE="$CERT_DIR/server-cert.pem"
KEY_FILE="$CERT_DIR/server-key.pem"
if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -days 365 \
        -subj "/CN=localhost" \
        -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"
fi
chown "$RUN_AS_USER:$RUN_AS_GROUP" "$CERT_FILE" "$KEY_FILE"
chmod 0600 "$KEY_FILE"

# Write the persistent local config.
LOCAL_CONFIG_FILE="$CONFIG_DIR/local.toml"
LOCAL_CONFIG_BACKUP_FILE="$LOCAL_CONFIG_FILE.bk"
if [[ -f "$LOCAL_CONFIG_FILE" ]]; then
    cp -p "$LOCAL_CONFIG_FILE" "$LOCAL_CONFIG_BACKUP_FILE"
    echo "Backed up existing local config to $LOCAL_CONFIG_BACKUP_FILE"
fi

cat > "$CONFIG_DIR/local.toml" <<EOF
[server.quic.certificate]
cert_file = "$CERT_FILE"
pkey_file = "$KEY_FILE"

[immutable_store]
mode = "local"

[mutable_store]
mode = "local"

[immutable_store.local]
path = "$DATA_ROOT"
flush_delay_seconds = 10

[mutable_store.local]
path = "$DATA_ROOT"
flush_delay_seconds = 10

[topology]
provider = "none"
EOF
chown "$RUN_AS_USER:$RUN_AS_GROUP" "$LOCAL_CONFIG_FILE"
chmod 0640 "$LOCAL_CONFIG_FILE"

# Write a systemd service that starts the server with the persistent config.
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Persistent Lore Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_AS_USER}
Group=${RUN_AS_GROUP}
WorkingDirectory=${REPO_ROOT}
Environment="LORE_CONFIG_PATH=${CONFIG_DIR}"
Environment="LORE_ENV=${ENV_NAME}"
ExecStart=${INSTALL_DIR}/loreserver --config ${CONFIG_DIR}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"

cat <<EOF
Persistent Lore installation complete.

Binary:        ${INSTALL_DIR}/loreserver
Config dir:    ${CONFIG_DIR}
Data root:     ${DATA_ROOT}
Cert:          ${CERT_FILE}
Key:           ${KEY_FILE}
Service:       ${SERVICE_NAME}

Notes:
- The data root is explicitly pinned to ${DATA_ROOT}, so this installation does not fall back to /tmp.
- The server is started via systemd using LORE_CONFIG_PATH=${CONFIG_DIR} and LORE_ENV=${ENV_NAME}.
- To inspect logs: journalctl -u ${SERVICE_NAME} -f
- To verify health: curl -sS http://127.0.0.1:41339/health_check
EOF
