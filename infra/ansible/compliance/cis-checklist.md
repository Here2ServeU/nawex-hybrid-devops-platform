# CIS Benchmark Checklist — NAWEX Linux Baseline

This checklist maps the NAWEX Linux baseline roles and scripts to CIS
Benchmark controls. Target profiles are **Ubuntu 22.04 LTS v2.0.0** and
**RHEL 9 v1.0.0**. Every item below is enforced by either the Ansible
baseline or [scripts/harden.sh](../scripts/harden.sh) — no manual steps.

Legend: **A** = Ansible role · **S** = shell script · **M** = manual.

## 1. Initial Setup

| CIS #  | Control                                    | Profile | Source        | Notes |
|--------|--------------------------------------------|---------|---------------|-------|
| 1.1.1  | Disable unused filesystems (cramfs, hfs…)  | L1      | A `system`    | modprobe blacklist |
| 1.5.x  | ASLR enabled                               | L1      | A `system` / S| `kernel.randomize_va_space=2` |
| 1.6.x  | AppArmor / SELinux enabled                 | L1      | A `security`  | distro-dependent |

## 2. Services

| CIS #  | Control                                    | Profile | Source        | Notes |
|--------|--------------------------------------------|---------|---------------|-------|
| 2.1.x  | Legacy inetd-style services disabled       | L1      | A `system`    | |
| 2.2.1  | Time sync configured (chrony)              | L1      | A `system`    | |

## 3. Network Configuration

| CIS #  | Control                                    | Profile | Source        | Notes |
|--------|--------------------------------------------|---------|---------------|-------|
| 3.2.1  | Source-routed packets rejected             | L1      | A `system` / S| `net.ipv4.conf.all.accept_source_route=0` |
| 3.2.2  | ICMP redirects rejected                    | L1      | A `system` / S| `net.ipv4.conf.all.accept_redirects=0` |
| 3.2.6  | TCP SYN cookies enabled                    | L1      | A `system` / S| `net.ipv4.tcp_syncookies=1` |

## 4. Logging and Auditing

| CIS #  | Control                                    | Profile | Source           | Notes |
|--------|--------------------------------------------|---------|------------------|-------|
| 4.1.1  | auditd enabled and running                 | L2      | A `security`     | See `compliance/audit-rules.conf` |
| 4.1.2  | Audit rules immutable                      | L2      | A `security`     | `-e 2` last line |
| 4.1.4  | Events for date/time tampering captured    | L2      | A `security`     | `time-change` key |
| 4.1.5  | Events for user/group changes captured     | L2      | A `security`     | `identity` key |
| 4.1.10 | DAC permission modifications captured      | L2      | A `security`     | `perm_mod` key |
| 4.1.11 | Unsuccessful file access captured          | L2      | A `security`     | `access` key |
| 4.1.13 | Use of privileged commands captured        | L2      | A `security`     | `privileged` key |
| 4.1.17 | Kernel module loading captured             | L2      | A `security`     | `modules` key |
| 4.2.x  | rsyslog running, forwarding configured     | L1      | A `observability`| |

## 5. Access, Authentication, Authorization

| CIS #  | Control                                    | Profile | Source        | Notes |
|--------|--------------------------------------------|---------|---------------|-------|
| 5.2.2  | SSH Protocol = 2                           | L1      | A / S         | |
| 5.2.5  | SSH LogLevel INFO or VERBOSE               | L1      | A / S         | VERBOSE |
| 5.2.7  | SSH MaxAuthTries ≤ 4                       | L1      | A / S         | |
| 5.2.8  | SSH PermitRootLogin = no                   | L1      | A / S         | |
| 5.2.10 | SSH PasswordAuthentication = no            | L1      | A / S         | key-based only |
| 5.2.13 | SSH ClientAlive (300s, max 2)              | L1      | A / S         | |

## 6. System Maintenance

| CIS #  | Control                                    | Profile | Source        | Notes |
|--------|--------------------------------------------|---------|---------------|-------|
| 6.1.x  | File permissions on /etc/passwd et al.     | L1      | A `system`    | |
| 6.2.x  | No accounts with UID 0 other than root     | L1      | A `security`  | drift check |

## Running the checklist

- **Fleet-wide.** `ansible-playbook infra/ansible/playbooks/linux-baseline.yml` enforces every row above.
- **Single host.** `sudo ./scripts/harden.sh` covers the L1 subset on hosts where Ansible cannot run.
- **Evidence collection.** `auditctl -l` shows the currently loaded rules (must match `audit-rules.conf`); `sshd -T` shows the effective SSH config; `sysctl -a | grep -E '^(net|kernel|fs)\.'` shows kernel posture. Archive these per-host in `/var/log/nawex/` for audit handoff.
