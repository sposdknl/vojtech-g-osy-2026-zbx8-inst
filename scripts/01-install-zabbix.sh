#!/usr/bin/env bash
# Instalace Zabbix 8.0 LTS + MariaDB + Apache + Agent 2 na Debian 13.
# Pri jakekoli chybe konci nenulovym kodem. Skript je opakovatelny.
set -Eeuo pipefail
trap 'echo "CHYBA: radek $LINENO, prikaz: $BASH_COMMAND" >&2' ERR

export DEBIAN_FRONTEND=noninteractive

ZBX_SERVER_NAME="${ZBX_SERVER_NAME:-}"
[ -n "$ZBX_SERVER_NAME" ] || ZBX_SERVER_NAME="Zabbix - Vojtech-G"   
ZBX_SERVER_NAME="${ZBX_SERVER_NAME//\'/}"
ZBX_TIMEZONE="${ZBX_TIMEZONE:-}"
[ -n "$ZBX_TIMEZONE" ] || ZBX_TIMEZONE="Europe/Prague"

DB_NAME="zabbix"
DB_USER="zabbix"
PASS_FILE="/etc/zabbix/.db_password"
REPO_DEB="zabbix-release_latest+debian13_all.deb"
REPO_URL="https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/${REPO_DEB}"

echo "==> [1/8] Zakladni balicky"
apt-get update -y
apt-get install -y wget ca-certificates openssl curl

echo "==> [2/8] Oficialni repozitar Zabbix 8.0"
if ! dpkg -s zabbix-release >/dev/null 2>&1; then
  wget -q -O "/tmp/${REPO_DEB}" "$REPO_URL"
  dpkg -i "/tmp/${REPO_DEB}"
  rm -f "/tmp/${REPO_DEB}"
fi
apt-get update -y

echo "==> [3/8] Instalace balicku (MariaDB, Zabbix server, frontend, Apache, agent 2)"
apt-get install -y mariadb-server \
  zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
  zabbix-sql-scripts zabbix-agent2
systemctl enable --now mariadb

echo "==> [4/8] Heslo k databazi (nikdy se nevypisuje)"
mkdir -p /etc/zabbix
if [ -n "${ZBX_DB_PASSWORD:-}" ]; then
  DB_PASS="$ZBX_DB_PASSWORD"                       # z prostredi hostitele
elif [ -s "$PASS_FILE" ]; then
  DB_PASS="$(cat "$PASS_FILE")"                    # z drivejsiho behu
else
  DB_PASS="$(openssl rand -hex 16)"                # nahodne vygenerovano
fi
if ! [[ "$DB_PASS" =~ ^[A-Za-z0-9_.-]{8,}$ ]]; then
  echo "Heslo musi mit >= 8 znaku z mnoziny A-Za-z0-9_.-" >&2; exit 1
fi
umask 077
printf '%s' "$DB_PASS" > "$PASS_FILE"
chmod 600 "$PASS_FILE"; chown root:root "$PASS_FILE"
umask 022

echo "==> [5/8] Databaze a uzivatel"
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Import schematu pouze jednou (kdyz tabulka 'users' jeste neexistuje)
HAS_SCHEMA="$(mariadb -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name='users';")"
if [ "$HAS_SCHEMA" = "0" ]; then
  echo "    importuji pocatecni schema a data (muze trvat minutu)"
  SQL_FILE="$(find /usr/share/zabbix* -type f -path '*mysql/server.sql.gz' 2>/dev/null | head -n1)"
  [ -n "$SQL_FILE" ] || { echo "server.sql.gz nenalezen" >&2; exit 1; }
  mariadb -e "SET GLOBAL log_bin_trust_function_creators = 1;"
  zcat "$SQL_FILE" | mariadb --default-character-set=utf8mb4 "$DB_NAME"
  mariadb -e "SET GLOBAL log_bin_trust_function_creators = 0;"
else
  echo "    schema uz existuje - import preskocen"
fi

echo "==> [6/8] Konfigurace Zabbix serveru, agenta a frontendu"
CONF=/etc/zabbix/zabbix_server.conf
for kv in "DBName=${DB_NAME}" "DBUser=${DB_USER}" "DBPassword=${DB_PASS}"; do
  key="${kv%%=*}"
  if grep -qE "^[#[:space:]]*${key}=" "$CONF"; then
    sed -i -E "s|^[#[:space:]]*${key}=.*|${kv}|" "$CONF"
  else
    echo "$kv" >> "$CONF"
  fi
done
chown root:zabbix "$CONF"; chmod 640 "$CONF"

# Agent 2: monitoruje lokalni server (Hostname = "Zabbix server")
AG=/etc/zabbix/zabbix_agent2.conf
sed -i -E 's|^Server=.*|Server=127.0.0.1|; s|^ServerActive=.*|ServerActive=127.0.0.1|; s|^Hostname=.*|Hostname=Zabbix server|' "$AG"

# PHP casova zona v Apache konfiguraci Zabbixu
APC=/etc/zabbix/apache.conf
if [ -f "$APC" ]; then
  sed -i -E "s|^\s*#?\s*php_value date.timezone .*|        php_value date.timezone ${ZBX_TIMEZONE}|" "$APC"
fi

# zabbix.conf.php - preskoci PHP wizard
mkdir -p /etc/zabbix/web
cat > /etc/zabbix/web/zabbix.conf.php <<PHP
<?php
// Generovano provisioning skriptem. Needitujte rucne.
\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = '${DB_NAME}';
\$DB['USER']     = '${DB_USER}';
\$DB['PASSWORD'] = '${DB_PASS}';
\$DB['SCHEMA']   = '';
\$DB['ENCRYPTION']        = false;
\$DB['KEY_FILE']          = '';
\$DB['CERT_FILE']         = '';
\$DB['CA_FILE']           = '';
\$DB['VERIFY_HOST']       = false;
\$DB['CIPHER_LIST']       = '';
\$DB['VAULT']             = '';
\$DB['VAULT_URL']         = '';
\$DB['VAULT_DB_PATH']     = '';
\$DB['VAULT_TOKEN']       = '';
\$DB['VAULT_CERT_FILE']   = '';
\$DB['VAULT_KEY_FILE']    = '';
\$DB['VAULT_CACHE']       = true;
\$DB['DOUBLE_IEEE754']    = true;

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '${ZBX_SERVER_NAME}';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
PHP
chown root:www-data /etc/zabbix/web/zabbix.conf.php
chmod 640 /etc/zabbix/web/zabbix.conf.php

echo "==> [7/8] Spusteni a povoleni sluzeb"
systemctl enable mariadb zabbix-server zabbix-agent2 apache2
systemctl restart mariadb zabbix-server zabbix-agent2 apache2

echo "==> [8/8] Hotovo. Web: http://127.0.0.1:8080/zabbix  (Admin / zabbix - ZMENTE heslo!)"
