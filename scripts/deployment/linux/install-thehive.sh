#!/usr/bin/env bash
set -euo pipefail

THEHIVE_VERSION="${THEHIVE_VERSION:-5.8.1-1}"
THEHIVE_BRANCH="${THEHIVE_BRANCH:-5.8}"
BASE_URL="${THEHIVE_BASE_URL:-http://10.30.0.21:9000}"
STRANGEBEE_FPR="0CD5AC59DE5C5A8E0EE138493D99BB18562CBC1C"
CQLSH_PYTHON=/usr/bin/python3.9
export CQLSH_PYTHON

usage() {
  cat <<USAGE
Usage: sudo $0 <step>

Run the steps in order on thehive01, checking the output of each before the next:
  java           Amazon Corretto 11 and JAVA_HOME
  cassandra      Cassandra 4.1 (41x repo), heap, cluster thp, auth on, localhost only,
                 roles admin (superuser) and thehive (keyspace thehive only), default role dropped
  elasticsearch  Elasticsearch 8.x, security on, HTTP on 127.0.0.1 without TLS, 1 GB heap,
                 elastic password reset, role and user thehive limited to thehive* indices
  thehive        TheHive ${THEHIVE_VERSION} from the signed .deb (SHA256 + GPG), credentials.conf,
                 baseUrl, heap; tests both thehive logins before the first start

Passwords are prompted for and never printed. Enter each one once per step from the
password manager: a mismatch between the account and credentials.conf stops TheHive.
USAGE
  exit 1
}

[[ $# -eq 1 ]] || usage
if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo on thehive01" >&2
  exit 1
fi

ask() {
  local __var=$1 __a __b
  read -rsp "$2: " __a; echo
  read -rsp "Again: " __b; echo
  [[ -n "$__a" && "$__a" == "$__b" ]] || { echo "Empty or not matching" >&2; exit 1; }
  printf -v "$__var" '%s' "$__a"
}

cql_as() {
  local user=$1 pw=$2 cred rc=0
  shift 2
  cred=$(mktemp)
  chmod 600 "$cred"
  printf '[PlainTextAuthProvider]\nusername = %s\npassword = %s\n' "$user" "$pw" > "$cred"
  cqlsh --credentials="$cred" -u "$user" "$@" || rc=$?
  rm -f "$cred"
  return $rc
}

es_as() {
  local user=$1 pw=$2
  shift 2
  curl -s -K <(printf 'user = "%s:%s"\n' "$user" "$pw") "$@"
  echo
}

step_java() {
  apt-get update -qq
  apt-get install -y wget curl gnupg coreutils apt-transport-https git ca-certificates ca-certificates-java software-properties-common python3-pip lsb-release unzip
  wget -qO- https://apt.corretto.aws/corretto.key | gpg --dearmor --yes -o /usr/share/keyrings/corretto.gpg
  echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" > /etc/apt/sources.list.d/corretto.sources.list
  apt-get update -qq && apt-get install -y java-common java-11-amazon-corretto-jdk
  grep -q JAVA_HOME /etc/environment || echo 'JAVA_HOME="/usr/lib/jvm/java-11-amazon-corretto"' >> /etc/environment
  java -version 2>&1 | head -1
  grep JAVA_HOME /etc/environment
}

wait_cassandra() {
  echo "Waiting for Cassandra (JMX on 7199 opens after the unit reports active)"
  for _ in $(seq 1 30); do
    if pgrep -f CassandraDaemon > /dev/null && nodetool status 2>/dev/null | grep -q '^UN'; then
      nodetool status | grep '^UN'
      return 0
    fi
    sleep 5
  done
  echo "Cassandra not up after 150 s: check /var/log/cassandra/system.log" >&2
  exit 1
}

step_cassandra() {
  local fresh=0 ADMIN_PW HIVE_PW
  wget -qO- https://downloads.apache.org/cassandra/KEYS | gpg --dearmor --yes -o /usr/share/keyrings/cassandra-archive.gpg
  echo "deb [signed-by=/usr/share/keyrings/cassandra-archive.gpg] https://debian.cassandra.apache.org 41x main" > /etc/apt/sources.list.d/cassandra.sources.list
  apt-get update -qq
  if ! dpkg -s cassandra > /dev/null 2>&1; then
    apt-get install -s cassandra | grep '^Inst'
    apt-get install -y cassandra
    fresh=1
  fi
  if [[ $fresh -eq 1 ]]; then
    systemctl stop cassandra || true
    rm -rf /var/lib/cassandra/*
  fi
  [[ -f /etc/cassandra/cassandra.yaml.orig ]] || cp /etc/cassandra/cassandra.yaml /etc/cassandra/cassandra.yaml.orig
  [[ -f /etc/cassandra/jvm-server.options.orig ]] || cp /etc/cassandra/jvm-server.options /etc/cassandra/jvm-server.options.orig
  grep -qE '^-Xmx' /etc/cassandra/jvm-server.options || printf '%s\n' '-Xms1g' '-Xmx1536m' '-Xmn200m' >> /etc/cassandra/jvm-server.options
  sed -i -e "s/^cluster_name: .*/cluster_name: 'thp'/" -e 's/^authenticator: .*/authenticator: PasswordAuthenticator/' -e 's/^authorizer: .*/authorizer: CassandraAuthorizer/' /etc/cassandra/cassandra.yaml
  grep -nE '^(cluster_name|authenticator|authorizer|listen_address|rpc_address):' /etc/cassandra/cassandra.yaml
  grep -nE '^-Xm[sxn]' /etc/cassandra/jvm-server.options
  systemctl enable --now cassandra
  wait_cassandra

  if [[ ! -x $CQLSH_PYTHON ]]; then
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get install -y python3.9
  fi
  grep -q CQLSH_PYTHON "/home/${SUDO_USER:-root}/.bashrc" 2>/dev/null || echo "export CQLSH_PYTHON=$CQLSH_PYTHON" >> "/home/${SUDO_USER:-root}/.bashrc"

  if ! cql_as cassandra cassandra -e "SELECT release_version FROM system.local;" > /dev/null 2>&1; then
    echo "Default cassandra role already gone: roles were set up earlier, nothing to do"
    return 0
  fi
  ask ADMIN_PW "New Cassandra admin (superuser) password"
  ask HIVE_PW "New Cassandra thehive password"
  printf "CREATE ROLE admin WITH PASSWORD = '%s' AND LOGIN = true AND SUPERUSER = true;\n" "$ADMIN_PW" | cql_as cassandra cassandra
  printf "DROP ROLE cassandra;\nCREATE KEYSPACE IF NOT EXISTS thehive WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};\nCREATE ROLE thehive WITH LOGIN = true AND PASSWORD = '%s';\nGRANT ALL PERMISSIONS ON KEYSPACE thehive TO thehive;\n" "$HIVE_PW" | cql_as admin "$ADMIN_PW"
  cql_as admin "$ADMIN_PW" -e "LIST ROLES;"
  cql_as thehive "$HIVE_PW" -e "DESCRIBE KEYSPACE thehive;" | head -3
  cql_as cassandra cassandra -e "SELECT now() FROM system.local;" > /dev/null 2>&1 && echo "WARNING: default cassandra login still works" || echo "Default cassandra login rejected (expected)"
  unset ADMIN_PW HIVE_PW
  ss -tlnp | grep -E ':9042|:7199'
}

step_elasticsearch() {
  local F=/etc/elasticsearch/elasticsearch.yml ESPW THPW
  wget -qO- https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor --yes -o /usr/share/keyrings/elasticsearch-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
  apt-get update -qq
  apt-get install -s elasticsearch | grep -E "^Inst|newly installed" || true
  dpkg -s elasticsearch > /dev/null 2>&1 || apt-get install -y elasticsearch > /dev/null
  dpkg -l elasticsearch | tail -1
  [[ -f $F.pre-thehive ]] || cp -p $F $F.pre-thehive
  sed -i '/^xpack.security.http.ssl:/,/^[^ ]/ s/^  enabled: true/  enabled: false/' $F
  sed -i 's/^http.host: 0.0.0.0/http.host: 127.0.0.1/' $F
  sed -i 's/^#cluster.name: .*/cluster.name: thp/' $F
  grep -q '^thread_pool.search.queue_size' $F || echo 'thread_pool.search.queue_size: 100000' >> $F
  printf '%s\n' -Xms1g -Xmx1g > /etc/elasticsearch/jvm.options.d/heap.options
  chown root:elasticsearch /etc/elasticsearch/jvm.options.d/heap.options && chmod 640 /etc/elasticsearch/jvm.options.d/heap.options
  grep -nE '^(cluster.name|http.host|xpack.security.enabled|thread_pool)' $F
  systemctl daemon-reload
  systemctl enable --now elasticsearch
  ss -tlnp | grep -E ':9200|:9300'

  echo "Set the elastic superuser password (Elasticsearch prompts twice):"
  /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -i
  ask ESPW "The elastic password you just set"
  es_as elastic "$ESPW" "http://127.0.0.1:9200/_cluster/health?pretty" | grep -E '"status"|cluster_name'
  es_as elastic "$ESPW" -X PUT http://127.0.0.1:9200/_security/role/thehive -H 'Content-Type: application/json' -d '{"cluster":["manage"],"indices":[{"names":["thehive*"],"privileges":["all"]}]}'
  ask THPW "New Elasticsearch thehive password"
  printf '{"password":"%s","roles":["thehive"]}' "$THPW" | es_as elastic "$ESPW" -X PUT http://127.0.0.1:9200/_security/user/thehive -H 'Content-Type: application/json' --data-binary @-
  es_as thehive "$THPW" "http://127.0.0.1:9200/_security/_authenticate?pretty" | grep -A2 '"roles"'
  unset ESPW THPW
}

step_thehive() {
  local deb="thehive_${THEHIVE_VERSION}_all.deb" CASS_PW ES_PW code
  cd /tmp
  wget -q "https://thehive.download.strangebee.com/${THEHIVE_BRANCH}/deb/${deb}"
  wget -q "https://thehive.download.strangebee.com/${THEHIVE_BRANCH}/sha256/${deb}.sha256"
  wget -q "https://thehive.download.strangebee.com/${THEHIVE_BRANCH}/asc/${deb}.asc"
  [[ "$(sha256sum "$deb" | cut -d' ' -f1)" == "$(grep -oE '[0-9a-f]{64}' "$deb.sha256")" ]] && echo "SHA256 MATCH" || { echo "SHA256 MISMATCH" >&2; exit 1; }
  wget -qO /tmp/strangebee.gpg https://keys.download.strangebee.com/latest/gpg/strangebee.gpg
  gpg --show-keys --with-colons /tmp/strangebee.gpg | awk -F: '/^fpr/{print $10; exit}' | grep -qx "$STRANGEBEE_FPR" || { echo "StrangeBee key fingerprint mismatch" >&2; exit 1; }
  gpg --import /tmp/strangebee.gpg 2>/dev/null
  gpg --verify "$deb.asc" "$deb"
  apt-get install -s "/tmp/$deb" | grep -E "^Inst|newly installed" || true
  dpkg -s thehive > /dev/null 2>&1 || apt-get install -y "/tmp/$deb" 2>&1 | tail -5
  systemctl stop thehive 2>/dev/null || true

  [[ -f /etc/thehive/application.conf.orig ]] || cp -p /etc/thehive/application.conf /etc/thehive/application.conf.orig
  ask CASS_PW "Cassandra thehive password"
  ask ES_PW "Elasticsearch thehive password"
  cql_as thehive "$CASS_PW" -e "SELECT keyspace_name FROM system_schema.keyspaces WHERE keyspace_name='thehive';" > /dev/null 2>&1 && echo "Cassandra login: OK" || { echo "Cassandra rejected the thehive password: fix it before starting TheHive" >&2; exit 1; }
  code=$(curl -s -o /dev/null -w "%{http_code}" -K <(printf 'user = "thehive:%s"\n' "$ES_PW") http://127.0.0.1:9200/)
  [[ $code == 200 ]] && echo "Elasticsearch login: OK" || { echo "Elasticsearch returned $code for thehive: fix it before starting TheHive" >&2; exit 1; }
  printf 'db.janusgraph.storage.username = "thehive"\ndb.janusgraph.storage.password = "%s"\ndb.janusgraph.index.search.elasticsearch.http.auth.type = basic\ndb.janusgraph.index.search.elasticsearch.http.auth.basic.username = "thehive"\ndb.janusgraph.index.search.elasticsearch.http.auth.basic.password = "%s"\n' "$CASS_PW" "$ES_PW" > /etc/thehive/credentials.conf
  unset CASS_PW ES_PW
  chown root:thehive /etc/thehive/credentials.conf && chmod 640 /etc/thehive/credentials.conf
  awk -F'"' '{print $1, (/password/ ? "<" length($2) " chars>" : $2)}' /etc/thehive/credentials.conf
  grep -q 'credentials.conf' /etc/thehive/application.conf || sed -i 's#^include "/etc/thehive/secret.conf"#&\ninclude "/etc/thehive/credentials.conf"#' /etc/thehive/application.conf
  sed -i "s#^application.baseUrl = .*#application.baseUrl = \"${BASE_URL}\"#" /etc/thehive/application.conf
  grep -q '^JAVA_OPTS' /etc/default/thehive 2>/dev/null || echo 'JAVA_OPTS="-Xms1g -Xmx1g -XX:MaxMetaspaceSize=400m -XX:ReservedCodeCacheSize=400m"' >> /etc/default/thehive
  grep -nE '^include|^application.baseUrl' /etc/thehive/application.conf

  systemctl enable --now thehive
  echo "Waiting for TheHive API"
  for _ in $(seq 1 36); do
    if curl -sf http://127.0.0.1:9000/api/status > /dev/null; then
      curl -s http://127.0.0.1:9000/api/status | head -c 200; echo
      rm -f "/tmp/$deb" "/tmp/$deb.sha256" "/tmp/$deb.asc" /tmp/strangebee.gpg
      return 0
    fi
    sleep 5
  done
  echo "No API after 3 min:" >&2
  grep "Caused by" /var/log/thehive/application.log | tail -4 | cut -c1-240 >&2
  exit 1
}

case $1 in
  java) step_java ;;
  cassandra) step_cassandra ;;
  elasticsearch) step_elasticsearch ;;
  thehive) step_thehive ;;
  *) usage ;;
esac
