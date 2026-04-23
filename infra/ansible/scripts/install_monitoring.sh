#!/usr/bin/env bash
#
# NAWEX Linux Baseline — install_monitoring.sh
#
# Installs Prometheus node_exporter as a dedicated system user with a
# sandboxed systemd unit. Safe to re-run; version upgrades happen by
# bumping NODE_EXPORTER_VERSION.

set -euo pipefail

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.8.2}"
NODE_EXPORTER_ARCH="${NODE_EXPORTER_ARCH:-linux-amd64}"
NODE_EXPORTER_LISTEN="${NODE_EXPORTER_LISTEN:-:9100}"
TARBALL="node_exporter-${NODE_EXPORTER_VERSION}.${NODE_EXPORTER_ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${TARBALL}"

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "install_monitoring.sh must run as root" >&2
        exit 1
    fi
}

ensure_user() {
    if ! id node_exporter >/dev/null 2>&1; then
        useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    fi
}

install_binary() {
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' RETURN
    curl -fsSL "${URL}" -o "${tmp}/${TARBALL}"
    tar -xzf "${tmp}/${TARBALL}" -C "${tmp}" --strip-components=1
    install -m 0755 -o root -g root "${tmp}/node_exporter" /usr/local/bin/node_exporter
}

install_unit() {
    cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus node_exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=${NODE_EXPORTER_LISTEN}
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now node_exporter
}

main() {
    require_root
    ensure_user
    install_binary
    install_unit
    systemctl status node_exporter --no-pager
}

main "$@"
