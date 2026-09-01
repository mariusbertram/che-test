#!/usr/bin/env bash
# Runs once on workspace start (devfile postStart event "setup-tools").
# Wires up the corporate proxy for git/pip/go/terraform/ansible and
# installs Ansible + Terraform (not part of the base universal-developer-image).
set -uo pipefail

PROFILE="$HOME/.bashrc"
touch "$PROFILE"

add_line_once() {
  grep -qxF "$1" "$PROFILE" 2>/dev/null || echo "$1" >> "$PROFILE"
}

echo "==> Configuring proxy"
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

  echo "    proxy applied: HTTP_PROXY=${HTTP_PROXY:-<empty>} HTTPS_PROXY=${HTTPS_PROXY:-<empty>} NO_PROXY=${NO_PROXY}"
  echo "    (Go, Terraform and ansible-galaxy read HTTP_PROXY/HTTPS_PROXY natively, no extra config needed.)"
else
  echo "    no HTTP_PROXY/HTTPS_PROXY set - skipping proxy setup (relying on cluster-level proxy, if any)."
fi

add_line_once 'export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"'
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$HOME/go/bin"

echo "==> Ansible"
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "    installing (pip3 install --user ansible)"
  pip3 install --user --quiet ansible || echo "    WARNING: ansible install failed, check proxy/pip.conf"
else
  echo "    already installed: $(ansible --version 2>/dev/null | head -n1)"
fi

echo "==> Terraform"
if ! command -v terraform >/dev/null 2>&1; then
  TF_VERSION="${TERRAFORM_VERSION:-}"
  if [ -z "$TF_VERSION" ]; then
    TF_VERSION=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform 2>/dev/null \
      | grep -o '"current_version":"[^"]*"' | cut -d'"' -f4)
  fi
  TF_VERSION="${TF_VERSION:-1.9.8}"

  case "$(uname -m)" in
    x86_64)  TF_ARCH=amd64 ;;
    aarch64|arm64) TF_ARCH=arm64 ;;
    *) TF_ARCH="" ;;
  esac

  if [ -n "$TF_ARCH" ]; then
    echo "    installing terraform ${TF_VERSION} (${TF_ARCH})"
    if curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip"; then
      unzip -o -q /tmp/terraform.zip -d "$HOME/.local/bin"
      chmod +x "$HOME/.local/bin/terraform"
      rm -f /tmp/terraform.zip
    else
      echo "    WARNING: terraform download failed, check proxy/NO_PROXY"
    fi
  else
    echo "    WARNING: unsupported architecture $(uname -m), skipping terraform install"
  fi
else
  echo "    already installed: $(terraform version 2>/dev/null | head -n1)"
fi

echo "==> Versions"
go version 2>/dev/null || true
python3 --version 2>/dev/null || true
ansible --version 2>/dev/null | head -n1 || true
terraform version 2>/dev/null | head -n1 || true
echo "==> setup-tools done."
