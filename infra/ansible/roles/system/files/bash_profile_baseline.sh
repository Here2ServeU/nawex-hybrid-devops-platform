# NAWEX Platform — Bash Environment Baseline
# Applied by the Ansible `system` role to all managed hosts (bare metal,
# vSphere VMs, cloud instances). Sourced from /etc/profile.d/ so it
# applies fleet-wide for interactive login shells regardless of whether
# a user has a personal ~/.bash_profile or ~/.bashrc.

# Source system-wide definitions so per-distro defaults still apply.
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# PATH additions for platform tooling. /opt/nawex/bin is the install
# prefix for operator-delivered binaries (kubectl, argocd, oc, tfsec).
export PATH="$PATH:/usr/local/bin:/opt/nawex/bin"

# Platform environment variables — default to production posture so an
# unset NAWEX_ENV does not silently relax safety rails.
export NAWEX_ENV="${NAWEX_ENV:-production}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Operational aliases. Kept minimal so shell muscle memory transfers
# between operators — add here, not to personal dotfiles.
alias ll='ls -alF'
alias k='kubectl'
alias tf='terraform'

# History settings — required for audit trails on regulated workloads.
# Timestamps + erasedups + large buffer means `history` output is usable
# as evidence during incident review.
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=ignoredups:erasedups
shopt -s histappend
