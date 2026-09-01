#!/usr/bin/env bash
# Runs once on workspace start (devfile postStart event "configure-proxy").
# Go, Terraform and ansible-galaxy read HTTP_PROXY/HTTPS_PROXY/NO_PROXY
# directly - only git and pip need an explicit config file.
set -uo pipefail

PROFILE="$HOME/.bashrc"
touch "$PROFILE"

add_line_once() {
  grep -qxF "$1" "$PROFILE" 2>/dev/null || echo "$1" >> "$PROFILE"
}

if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
  EXTRA_NO_PROXY="localhost,127.0.0.1,.svc,.cluster.local"
  [ -n "${KUBERNETES_SERVICE_HOST:-}" ] && EXTRA_NO_PROXY="${EXTRA_NO_PROXY},${KUBERNETES_SERVICE_HOST}"
  export NO_PROXY="${NO_PROXY:-},${EXTRA_NO_PROXY}"
  export no_proxy="${NO_PROXY}"
  add_line_once "export NO_PROXY=\"${NO_PROXY}\""
  add_line_once "export no_proxy=\"${NO_PROXY}\""

  [ -n "${HTTP_PROXY:-}" ]  && git config --global http.proxy  "${HTTP_PROXY}"
  [ -n "${HTTPS_PROXY:-}" ] && git config --global https.proxy "${HTTPS_PROXY}"

  mkdir -p "$HOME/.config/pip"
  {
    echo "[global]"
    [ -n "${HTTPS_PROXY:-}" ] && echo "proxy = ${HTTPS_PROXY}"
    echo "timeout = ${PIP_DEFAULT_TIMEOUT:-100}"
  } > "$HOME/.config/pip/pip.conf"

  echo "Proxy applied: HTTP_PROXY=${HTTP_PROXY:-<empty>} HTTPS_PROXY=${HTTPS_PROXY:-<empty>} NO_PROXY=${NO_PROXY}"
else
  echo "No HTTP_PROXY/HTTPS_PROXY set - skipping proxy setup (relying on cluster-level proxy, if any)."
fi

echo "Tool versions:"
go version 2>/dev/null || true
python3 --version 2>/dev/null || true
terraform version 2>/dev/null | head -n1 || true
ansible --version 2>/dev/null | head -n1 || true
