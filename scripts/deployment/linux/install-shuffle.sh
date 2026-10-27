#!/usr/bin/env bash
set -euo pipefail

SHUFFLE_TAG="${SHUFFLE_TAG:-v2.3.0}"
IMAGE_TAG="${SHUFFLE_TAG#v}"
DIR="${SHUFFLE_DIR:-$HOME/Shuffle}"
HEAP="${OPENSEARCH_HEAP:-2g}"
DOCKER_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

usage() {
  cat <<USAGE
Usage: $0 <step>     (run as caleb, not root; uses sudo for Docker)

Steps, in order, on shuffle01:
  docker   Docker Engine and Compose from Docker's signed apt repo (key fingerprint checked)
  prepare  Clone Shuffle at ${SHUFFLE_TAG} into ${DIR}, pin images to ${IMAGE_TAG}
           (shuffle-security stays on latest: it has no ${IMAGE_TAG} tag), OpenSearch heap ${HEAP},
           OpenSearch/backend/security ports bound to 127.0.0.1, generated OpenSearch password and
           encryption key in .env (only on the first run: the key must never change), TZ=UTC
  up       Validate the compose file, pull, start, and show containers and listeners

The caleb account is not added to the docker group: membership is root without a password.
Leave vm.max_map_count at Ubuntu's default (1048576); a 262144 sysctl file lowers it.
USAGE
  exit 1
}

[[ $# -eq 1 ]] || usage
if [[ $EUID -eq 0 ]]; then
  echo "Run as your own user; the script calls sudo where needed" >&2
  exit 1
fi

step_docker() {
  sudo apt-get update -qq
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc | awk -F: '/^fpr/{print $10; exit}' | grep -qx "$DOCKER_FPR" || { echo "Docker key fingerprint mismatch" >&2; exit 1; }
  echo "Docker key fingerprint OK"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update 2>&1 | grep -iE "docker|err" || true
  apt-get -s install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin | grep -E "^Inst|newly installed"
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo docker version --format 'Docker {{.Server.Version}}'
  sudo docker compose version
  echo "docker: $(systemctl is-active docker), $(systemctl is-enabled docker)"
}

step_prepare() {
  local P
  [[ -d $DIR/.git ]] || git clone https://github.com/Shuffle/Shuffle "$DIR"
  cd "$DIR"
  git fetch --tags -q
  git checkout -q "$SHUFFLE_TAG"
  git log --oneline -1

  grep -oE 'ghcr.io/shuffle/shuffle-[a-z-]+' docker-compose.yml | sort -u | while read -r i; do
    sudo docker manifest inspect "$i:$IMAGE_TAG" > /dev/null 2>&1 && echo "$i:$IMAGE_TAG ok" || echo "$i:$IMAGE_TAG MISSING"
  done
  sed -i "s#\(ghcr.io/shuffle/shuffle-[a-z-]*\):latest#\1:${IMAGE_TAG}#g" docker-compose.yml
  sed -i "s#ghcr.io/shuffle/shuffle-security:${IMAGE_TAG}#ghcr.io/shuffle/shuffle-security:latest#" docker-compose.yml
  sed -i "s/-Xms[0-9]*[mg] -Xmx[0-9]*[mg]/-Xms${HEAP} -Xmx${HEAP}/" docker-compose.yml
  sed -i 's#- 9200:9200#- "127.0.0.1:9200:9200"#' docker-compose.yml
  sed -i 's#- "${BACKEND_PORT}:5001"#- "127.0.0.1:${BACKEND_PORT}:5001"#' docker-compose.yml
  sed -i -e 's#- "${SHUFFLE_SECURITY_PORT:-3002}:80"#- "127.0.0.1:${SHUFFLE_SECURITY_PORT:-3002}:80"#' -e 's#- "${SHUFFLE_SECURITY_PORT_HTTPS:-3444}:443"#- "127.0.0.1:${SHUFFLE_SECURITY_PORT_HTTPS:-3444}:443"#' docker-compose.yml
  grep -nE 'image: ghcr|OPENSEARCH_JAVA_OPTS|127.0.0.1:' docker-compose.yml

  if [[ -f .env.orig ]]; then
    echo ".env.orig exists: secrets were generated on an earlier run, leaving .env alone"
  else
    cp -p .env .env.orig
    P="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | cut -c1-28)_Aa1"
    sed -i -e "s|^SHUFFLE_OPENSEARCH_PASSWORD=.*|SHUFFLE_OPENSEARCH_PASSWORD=\"$P\"|" -e "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=\"$P\"|" .env
    unset P
    sed -i -e "s|^SHUFFLE_ENCRYPTION_MODIFIER=.*|SHUFFLE_ENCRYPTION_MODIFIER=$(openssl rand -hex 32)|" -e 's|^TZ=.*|TZ=UTC|' .env
  fi
  chmod 600 .env .env.orig
  awk -F= '/^(SHUFFLE_OPENSEARCH_PASSWORD|OPENSEARCH_INITIAL_ADMIN_PASSWORD|SHUFFLE_ENCRYPTION_MODIFIER)=/{print $1, "<" length($2) " chars>"} /^TZ=/' .env
  sysctl vm.max_map_count
}

step_up() {
  cd "$DIR"
  sudo docker compose config --quiet && echo "compose OK"
  sudo docker compose pull
  sudo docker compose up -d
  sleep 20
  sudo docker compose ps --format 'table {{.Name}}\t{{.Status}}'
  sudo ss -tlnp | grep -E ':(3001|3443|5001|9200|3002|3444)\b'
  echo "Only 3001 and 3443 should be on 0.0.0.0. Next: scripts/troubleshooting/check-shuffle.sh"
}

case $1 in
  docker) step_docker ;;
  prepare) step_prepare ;;
  up) step_up ;;
  *) usage ;;
esac
