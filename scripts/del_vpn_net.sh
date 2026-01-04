#!/usr/bin/env bash
set -e

echo "[del_vpn_net.sh] Удаление Docker сети vpn-net..."
docker network inspect vpn-net >/dev/null 2>&1 || {
  echo "[del_vpn_net.sh] Сеть vpn-net не существует"
  exit 0
}

docker network rm vpn-net
echo "[del_vpn_net.sh] Сеть vpn-net удалена успешно"
