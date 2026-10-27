#!/usr/bin/env bash
set -euo pipefail

VERSION="${VELO_VERSION:-0.77.1}"
SERVER_IP="${VELO_SERVER_IP:-10.30.0.22}"
DIR="${VELO_DIR:-/root/velo}"
KEY_FPR="0572F28B4EF19A043F4CBBE0B22A7FB19CB6CFA1"
BIN="$DIR/velociraptor-v${VERSION}-linux-amd64"
REL="https://github.com/Velocidex/velociraptor/releases/download/v${VERSION}"

usage() {
  cat <<USAGE
Usage: $0 <step>     (root on velo01)

Steps, in order:
  download   curl and gnupg if missing, the Linux binary and .sig into ${DIR}
  verify     GPG check of the binary against Velocidex's key (${KEY_FPR})
  generate   The interactive config wizard under umask 077 (self-signed, DNS none,
             frontend hostname ${SERVER_IP}, ports 8000/8889, GUI user)
  package    Derive client.config.yaml (0.77's wizard doesn't write one; checks it holds no
             private key), move only the GUI bind to ${SERVER_IP}, build the server .deb
  install    Install the .deb (systemd velociraptor_server as user velociraptor) and check
             the service, listeners, memory and GUI users

server.config.yaml, its .orig and the server .deb all contain the CA private key.
Next: scripts/deployment/linux/build-velociraptor-msi.sh for Windows clients.
USAGE
  exit 1
}

[[ $# -eq 1 ]] || usage
if [[ $EUID -ne 0 ]]; then
  echo "Run as root on velo01" >&2
  exit 1
fi
mkdir -p "$DIR"
cd "$DIR"

step_download() {
  command -v curl > /dev/null || apt-get install -y curl
  command -v gpg > /dev/null || apt-get install -y gnupg
  curl -fsSLO "$REL/velociraptor-v${VERSION}-linux-amd64"
  curl -fsSLO "$REL/velociraptor-v${VERSION}-linux-amd64.sig"
  ls -l "$BIN" "$BIN.sig"
}

step_verify() {
  gpg --list-keys "$KEY_FPR" > /dev/null 2>&1 || gpg --keyserver hkps://keys.openpgp.org --recv-keys "$KEY_FPR"
  gpg --status-fd 1 --verify "$BIN.sig" "$BIN" 2>/dev/null | grep -q "VALIDSIG $KEY_FPR" || { echo "Signature check FAILED: delete the binary" >&2; exit 1; }
  echo "Good signature from $KEY_FPR"
  chmod 0755 "$BIN"
  "$BIN" version | head -3
  sha256sum "$BIN"
}

step_generate() {
  [[ -f server.config.yaml ]] && { echo "server.config.yaml already exists; move it away first to regenerate" >&2; exit 1; }
  ( umask 077 && "$BIN" config generate -i )
  ls -l server.config.yaml
  grep -nE "^\S|bind_address|bind_port|hostname" server.config.yaml | grep -E "^[0-9]+:(GUI|API|Frontend|Client)|bind_|hostname" | head -20
}

step_package() {
  ( umask 077 && "$BIN" --config server.config.yaml config client > client.config.yaml )
  grep -A1 "server_urls" client.config.yaml
  [[ $(grep -c "PRIVATE KEY" client.config.yaml) -eq 0 ]] && echo "client.config.yaml: no private key (expected)" || { echo "client.config.yaml contains a private key: do not distribute" >&2; exit 1; }
  [[ -f server.config.yaml.orig ]] || cp -p server.config.yaml server.config.yaml.orig
  sed -i "/^GUI:/,/bind_port/s/bind_address: 127.0.0.1/bind_address: ${SERVER_IP}/" server.config.yaml
  grep -nA2 "^GUI:" server.config.yaml
  "$BIN" --config server.config.yaml debian server --binary "$BIN" > /dev/null 2>&1
  ls -l ./*.deb
}

step_install() {
  local deb
  deb=$(ls velociraptor-server-*.deb 2>/dev/null | head -1)
  [[ -n $deb ]] || { echo "No velociraptor-server-*.deb (the name uses hyphens and dots): run package" >&2; exit 1; }
  dpkg -i "$deb" 2>&1 | tail -4
  sleep 10
  echo "velociraptor_server: $(systemctl is-active velociraptor_server), $(systemctl is-enabled velociraptor_server)"
  ss -tlnp | grep -E ':(8000|8001|8003|8889)\b'
  free -h | head -2
  grep -nA4 "initial_users" /etc/velociraptor/server.config.yaml | grep -E "initial_users|name:"
  echo "GUI: https://${SERVER_IP}:8889 (self-signed certificate warning expected)"
}

case $1 in
  download) step_download ;;
  verify) step_verify ;;
  generate) step_generate ;;
  package) step_package ;;
  install) step_install ;;
  *) usage ;;
esac
