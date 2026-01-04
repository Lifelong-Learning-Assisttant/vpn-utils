#!/usr/bin/env bash
set -e

echo "[make_vpn_net.sh] Создание Docker сети vpn-net..."
docker network inspect vpn-net >/dev/null 2>&1 && {
  echo "[make_vpn_net.sh] Сеть vpn-net уже существует"
  exit 0
}

docker network create vpn-net
echo "[make_vpn_net.sh] Сеть vpn-net создана успешно"
