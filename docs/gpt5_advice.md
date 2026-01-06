Отлично — текущая таблица уже в правильном виде: DNAT для `11650` остался (нужен для доступа к `code-server`), а `POSTROUTING` теперь маскарадует только подсеть `10.200.1.0/24`. Это ровно то, что мы хотели — хост сохранил доступ к интернету, а трафик из namespace корректно NAT’ится.

Чтобы полностью убрать риск повторного «слома» и впредь безопасно запускать/останавливать code-server в namespace, ниже — готовый **исправленный** `run-vscode-in-vpn-ns.sh`. Он:

* делает ограниченный DNAT для порта (как у тебя),
* предпочитает ставить MASQUERADE **внутри namespace** через `tun0` (если `tun0` есть) — это безопаснее, потому что правило живёт в пространстве имён и не ломает хост,
* если `tun0` в namespace отсутствует, ставит резервный `POSTROUTING` на хост — **только** для `10.200.1.0/24`,
* добавляет `trap cleanup` — при выходе скрипта / Ctrl-C правила и veth-пара очищаются,
* делает бэкап существующих правил перед изменениями (на случай отката).

Скопируй этот файл и замени текущий `vpn-utils/scripts/run-vscode-in-vpn-ns.sh` (или сохрани как `run-vscode-in-vpn-ns-safe.sh`), затем запускай через `sudo`.

```bash
#!/bin/bash
# safe run-vscode-in-vpn-ns.sh
# Запускает code-server в network namespace vpn-ns с VPN
# Безопаснее для хоста: masquerade делаем в namespace (tun0) или, при отсутствии tun0, только для подсети veth.

set -euo pipefail

VPN_NS="vpn-ns"
CODESERVER_PORT="${CODESERVER_PORT:-11650}"
CODESERVER_DIR="${CODESERVER_DIR:-$HOME/.local/share/code-server}"
VETH_HOST="veth-code-host"
VETH_NS="veth-code-ns"
VETH_SUBNET="10.200.1.0/24"
VETH_HOST_IP="10.200.1.1/24"
VETH_NS_IP="10.200.1.2/24"
BACKUP_DIR="/tmp/iptables-backups-$(date +%F_%T)"

# -- cleanup function (будет вызван при выходе)
cleanup() {
  echo "Cleanup: удаляем правила и интерфейсы..."
  # удалить PREROUTING DNAT
  iptables -t nat -D PREROUTING -p tcp --dport "$CODESERVER_PORT" -j DNAT --to-destination 10.200.1.2:"$CODESERVER_PORT" 2>/dev/null || true

  # попытаться удалить MASQUERADE внутри namespace (tun0)
  if ip netns list | grep -qw "$VPN_NS"; then
    ip netns exec "$VPN_NS" iptables -t nat -D POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || true
  fi

  # удалить резервный хостовый MASQUERADE (для подсети) если был добавлен
  iptables -t nat -D POSTROUTING -s "${VETH_SUBNET}" -j MASQUERADE 2>/dev/null || true

  # удалить veth (удаление хоста удалит и peer в namespace)
  ip link delete "$VETH_HOST" 2>/dev/null || true

  echo "Cleanup: завершён."
}

trap cleanup EXIT INT TERM

# Проверки
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен запускаться с правами root (sudo)." >&2
  exit 1
fi

if ! ip netns list | grep -qw "$VPN_NS"; then
  echo "Network namespace '$VPN_NS' не найден." >&2
  exit 1
fi

if ! command -v code-server &>/dev/null; then
  echo "code-server не найден. Установи его." >&2
  exit 1
fi

mkdir -p "$CODESERVER_DIR"
mkdir -p "$BACKUP_DIR"

echo "Сохраняем текущие правила iptables в $BACKUP_DIR"
iptables-save > "$BACKUP_DIR/iptables-before.save"

# Удаляем старые veth'ы с такими именами, если они остались
ip link delete "$VETH_HOST" 2>/dev/null || true
ip netns exec "$VPN_NS" ip link delete "$VETH_NS" 2>/dev/null || true

# Создаем veth-пару и задаём IP
ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
ip link set "$VETH_NS" netns "$VPN_NS"

ip addr add "$VETH_HOST_IP" dev "$VETH_HOST"
ip link set "$VETH_HOST" up

ip netns exec "$VPN_NS" ip addr add "$VETH_NS_IP" dev "$VETH_NS"
ip netns exec "$VPN_NS" ip link set "$VETH_NS" up

# DNAT: проброс порта с хоста на namespace (как раньше)
iptables -t nat -A PREROUTING -p tcp --dport "$CODESERVER_PORT" -j DNAT --to-destination 10.200.1.2:"$CODESERVER_PORT"

# MASQUERADE: предпочитаем делать внутри namespace через tun0
if ip netns exec "$VPN_NS" ip link show tun0 &>/dev/null; then
  echo "tun0 найден внутри $VPN_NS — добавляем MASQUERADE внутри namespace (по интерфейсу tun0)"
  # если нет iptables в ns — ip netns exec вызовет системный iptables; обычно доступно
  ip netns exec "$VPN_NS" iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
else
  echo "tun0 не найден внутри $VPN_NS — ставим резервный MASQUERADE на хосте только для подсети $VETH_SUBNET"
  iptables -t nat -A POSTROUTING -s "${VETH_SUBNET}" -j MASQUERADE
fi

# Информируем, как к нам подключиться
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Запускаем code-server в namespace $VPN_NS на порту $CODESERVER_PORT"
echo "Доступ: http://${HOST_IP}:${CODESERVER_PORT}"
echo "Пароль: в ~/.config/code-server/config.yaml у пользователя, от которого запускаем."

# Получаем текущего пользователя, но если не получилось — используем SUDO_USER
CURRENT_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-root}")

# Передаем переменные прокси — ВАЖНО:
# Если tinyproxy/HTTP proxy запускается на хосте и слушает на 127.0.0.1:1090,
# то внутри namespace 127.0.0.1 это loopback namespace — не тот. Если proxy запущен на хосте,
# используйте вместо 127.0.0.1 IP хоста в veth-сети: 10.200.1.1:1090
# Здесь мы пробуем автоматически:
PROXY_HOST="127.0.0.1:1090"
# если tinyproxy слушает на хосте по 0.0.0.0:1090 — лучше использовать 10.200.1.1
# проверяем на хосте:
if ss -tlnp | grep -q ':1090'; then
  # но внутри namespace 127.0.0.1 может не работать; используем адрес veth-хоста
  PROXY_HOST="10.200.1.1:1090"
fi

# Запускаем code-server в namespace от имени пользователя
ip netns exec "$VPN_NS" sudo -u "$CURRENT_USER" bash -c "
  export http_proxy=http://$PROXY_HOST
  export https_proxy=http://$PROXY_HOST
  export HTTP_PROXY=http://$PROXY_HOST
  export HTTPS_PROXY=http://$PROXY_HOST

  exec code-server --bind-addr 0.0.0.0:$CODESERVER_PORT --auth password --disable-telemetry --user-data-dir \"$CODESERVER_DIR\"
"

# exit -> cleanup via trap
```

---

### Инструкции по использованию и тестам (сразу после запуска / после остановки)

1. Запусти скрипт в `tmux` как `sudo`:

   ```bash
   sudo bash run-vscode-in-vpn-ns-safe.sh
   ```
2. Проверить, что хост видит интернет:

   ```bash
   curl -sS --max-time 5 ifconfig.me
   ```
3. Проверить, что namespace видит интернет (через VPN):

   ```bash
   sudo ip netns exec vpn-ns curl -sS --max-time 5 ifconfig.me
   ```
4. Проверить iptables:

   ```bash
   sudo iptables -t nat -L PREROUTING --line-numbers -n
   sudo iptables -t nat -L POSTROUTING --line-numbers -n
   # и внутри namespace (если поставили MASQ внутри)
   sudo ip netns exec vpn-ns iptables -t nat -L POSTROUTING --line-numbers -n || true
   ```
5. Проверь в VS Code — расширения/нейросети (они должны работать). Если что-то не работает — перезапусти remote session в VS Code.

---

### Если в системе есть `netfilter-persistent` / `iptables-persistent`

Проверь `/etc/iptables/rules.v4` и убедись, что там нет старого глобального `MASQUERADE` или DNAT, который будет восстанавливаться. Если есть — сделай бэкап и отредактируй, заменив глобальный MASQ на ограниченный `-s 10.200.1.0/24` или удалив его (мы уже добавляем правила временно).

```bash
sudo cp /etc/iptables/rules.v4 /tmp/rules.v4.bak
sudo sed -n '1,200p' /etc/iptables/rules.v4
# отредактируй вручную
sudo systemctl restart netfilter-persistent
```

---

Если хочешь — могу:

* подправить скрипт конкретно под твой setup (например заменить `PROXY_HOST` на конкретный адрес, если tinyproxy слушает по-иному), или
* сгенерировать короткий `systemd` unit / socket-forwarder (альтернатива DNAT), чтобы совсем не трогать iptables хоста.

Сейчас, судя по твоему выводу, всё в порядке — DNAT + ограниченный MASQ. Если хочешь — я дам короткие команды, чтобы удалить DNAT (временно) или показать текущие логи расширений VS Code.
