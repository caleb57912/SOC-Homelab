#!/usr/bin/env bash
set -euo pipefail

VERSION="${VELO_VERSION:-0.77.1}"
DIR="${VELO_DIR:-/root/velo}"
KEY_FPR="0572F28B4EF19A043F4CBBE0B22A7FB19CB6CFA1"
BIN="$DIR/velociraptor-v${VERSION}-linux-amd64"
MSI="velociraptor-v${VERSION}-windows-amd64.msi"
OUT="${1:-velo-client-${VERSION}-soc.msi}"
REL="https://github.com/Velocidex/velociraptor/releases/download/v${VERSION}"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root on velo01: $0 [output.msi]" >&2
  exit 1
fi
cd "$DIR"
[[ -x $BIN && -f client.config.yaml ]] || { echo "Needs $BIN and $DIR/client.config.yaml (install-velociraptor-server.sh package)" >&2; exit 1; }
[[ $(grep -c "PRIVATE KEY" client.config.yaml) -eq 0 ]] || { echo "client.config.yaml contains a private key: stop" >&2; exit 1; }
command -v curl > /dev/null || apt-get install -y curl
command -v gpg > /dev/null || apt-get install -y gnupg

echo "[1/4] Download"
[[ -f $MSI ]] || curl -fsSLO "$REL/$MSI"
[[ -f $MSI.sig ]] || curl -fsSLO "$REL/$MSI.sig"
ls -l "$MSI" "$MSI.sig"

echo "[2/4] Verify the vendor MSI before changing it"
gpg --list-keys "$KEY_FPR" > /dev/null 2>&1 || gpg --keyserver hkps://keys.openpgp.org --recv-keys "$KEY_FPR"
gpg --status-fd 1 --verify "$MSI.sig" "$MSI" 2>/dev/null | grep -q "VALIDSIG $KEY_FPR" || { echo "Signature check FAILED: delete $MSI" >&2; exit 1; }
echo "Good signature from $KEY_FPR"

echo "[3/4] Repack with client.config.yaml"
"$BIN" config repack --msi "$MSI" client.config.yaml "$OUT" > /dev/null 2>&1
ls -l "$MSI" "$OUT"

echo "[4/4] Hash to check after the transfer"
sha256sum "$OUT"
cat <<NEXT
The repacked MSI no longer carries the vendor's Authenticode signature ("unknown publisher").
Copy it out from pve:  scripts/maintenance/lxc-copy.sh pull 307 $DIR/$OUT /root/$OUT
Install on Windows:    scripts/deployment/windows/Install-VelociraptorClient.ps1 -Msi <path> -ExpectedSha256 <hash above>
NEXT
