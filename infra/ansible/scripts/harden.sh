#!/usr/bin/env bash
#
# NAWEX Linux Baseline — harden.sh
#
# Idempotent, no-Ansible hardening for a single host. Use on bootstrap nodes,
# jump hosts, rescue environments, or anywhere Ansible cannot run. For fleet-
# wide enforcement prefer ../playbooks/linux-baseline.yml.
#
# Applies the same controls as the `system` + `security` roles:
#   - SSH hardening (no root login, no password auth, short idle window)
#   - Kernel sysctl hardening
#   - auditd loaded with the NAWEX CIS-aligned ruleset

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_RULES_SRC="${SCRIPT_DIR}/../compliance/audit-rules.conf"

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        echo "harden.sh must run as root" >&2
        exit 1
    fi
}

harden_sshd() {
    local cfg=/etc/ssh/sshd_config
    declare -A settings=(
        [Protocol]="2"
        [PermitRootLogin]="no"
        [PasswordAuthentication]="no"
        [PermitEmptyPasswords]="no"
        [X11Forwarding]="no"
        [MaxAuthTries]="4"
        [ClientAliveInterval]="300"
        [ClientAliveCountMax]="2"
        [LogLevel]="VERBOSE"
    )
    for key in "${!settings[@]}"; do
        if grep -qE "^#?${key} " "${cfg}"; then
            sed -i -E "s|^#?${key} .*|${key} ${settings[${key}]}|" "${cfg}"
        else
            printf '%s %s\n' "${key}" "${settings[${key}]}" >>"${cfg}"
        fi
    done
    sshd -t
    systemctl reload sshd
}

harden_sysctl() {
    install -m 0644 /dev/stdin /etc/sysctl.d/99-nawex.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF
    sysctl --system >/dev/null
}

install_audit_rules() {
    if [[ ! -f "${AUDIT_RULES_SRC}" ]]; then
        echo "skipping auditd rules (missing ${AUDIT_RULES_SRC})" >&2
        return 0
    fi
    install -m 0640 "${AUDIT_RULES_SRC}" /etc/audit/rules.d/nawex.rules
    if command -v augenrules >/dev/null; then
        augenrules --load
    else
        systemctl restart auditd || service auditd restart
    fi
    systemctl enable auditd >/dev/null 2>&1 || true
}

main() {
    require_root
    harden_sshd
    harden_sysctl
    install_audit_rules
    echo "NAWEX baseline hardening applied."
}

main "$@"
