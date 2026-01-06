#!/bin/bash
# Безопасная версия скрипта для запуска code-server в network namespace vpn-ns с VPN
# Основана на рекомендациях от GPT5 для предотвращения потери связи

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VPN_NS="vpn-ns"
CODESERVER_PORT="${CODESERVER_PORT:-11650}"
CODESERVER_DIR="${CODESERVER_DIR:-$HOME/.local/share/code-server}"
VETH_HOST="veth-code-host"
VETH_NS="veth-code-ns"
VETH_SUBNET="10.200.1.0/24"
VETH_HOST_IP="10.200.1.1/24"
VETH_NS_IP="10.200.1.2/24"
BACKUP_DIR="/tmp/iptables-backups-$(date +%F_%T)"

# Cleanup function - будет вызван при выходе скрипта / Ctrl-C
cleanup() {
    echo -e "${YELLOW}Cleanup: удаляем правила и интерфейсы...${NC}"
    
    # Удаляем PREROUTING DNAT для порта code-server
    iptables -t nat -D PREROUTING -p tcp --dport "$CODESERVER_PORT" -j DNAT --to-destination 10.200.1.2:"$CODESERVER_PORT" 2>/dev/null || true
    
    # Пытаемся удалить MASQUERADE внутри namespace (tun0)
    if ip netns list | grep -qw "$VPN_NS"; then
        ip netns exec "$VPN_NS" iptables -t nat -D POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || true
    fi
    
    # Удаляем резервный хостовый MASQUERADE (для подсети) если был добавлен
    iptables -t nat -D POSTROUTING -s "${VETH_SUBNET}" -j MASQUERADE 2>/dev/null || true
    
    # Удаляем правила FORWARD для подсети veth
    iptables -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -s "${VETH_SUBNET}" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -d "${VETH_SUBNET}" -j ACCEPT 2>/dev/null || true
    
    # Удаляем veth (удаление хоста удалит и peer в namespace)
    ip link delete "$VETH_HOST" 2>/dev/null || true
    
    echo -e "${GREEN}Cleanup: завершён.${NC}"
}

# Устанавливаем trap для автоматической очистки при выходе
trap cleanup EXIT INT TERM

echo -e "${GREEN}=== Запуск code-server в network namespace $VPN_NS с VPN (безопасная версия) ===${NC}"
echo ""

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Этот скрипт должен запускаться с правами root${NC}"
    echo -e "${YELLOW}Используйте: sudo $0${NC}"
    exit 1
fi

# Проверка namespace
if ! ip netns list | grep -qw "$VPN_NS"; then
    echo -e "${RED}Network namespace '$VPN_NS' не существует${NC}"
    exit 1
fi

# Проверка VPN
if ! ip netns exec "$VPN_NS" ip link show tun0 &>/dev/null; then
    echo -e "${YELLOW}⚠️  VPN не подключён (интерфейс tun0 не найден)${NC}"
    echo -e "${YELLOW}Трафик будет идти напрямую, без VPN${NC}"
    echo ""
else
    VPN_IP=$(ip netns exec "$VPN_NS" curl -s ifconfig.me 2>/dev/null || echo "")
    if [ -n "$VPN_IP" ]; then
        echo -e "${GREEN}✓ VPN подключён${NC}"
        echo -e "${GREEN}  IP: $VPN_IP${NC}"
        echo ""
    else
        echo -e "${YELLOW}⚠️  VPN интерфейс есть, но IP не получен${NC}"
        echo ""
    fi
fi

# Проверка code-server
if ! command -v code-server &>/dev/null; then
    echo -e "${RED}code-server не найден${NC}"
    echo -e "${YELLOW}Установите его:${NC}"
    echo "  curl -fsSL https://code-server.dev/install.sh | sh"
    exit 1
fi

# Проверка версии code-server
CODESERVER_VERSION=$(code-server --version 2>/dev/null || echo "unknown")
echo -e "${GREEN}✓ code-server установлен${NC}"
echo -e "${GREEN}  Версия: $CODESERVER_VERSION${NC}"
echo ""

# Создание директории для бэкапа iptables
mkdir -p "$BACKUP_DIR"

# Сохраняем текущие правила iptables
echo -e "${BLUE}Сохраняем текущие правила iptables в $BACKUP_DIR${NC}"
iptables-save > "$BACKUP_DIR/iptables-before.save"

# Проверка и настройка проброса порта
if ! ip netns exec "$VPN_NS" ss -tlnp | grep -q ":$CODESERVER_PORT"; then
    echo -e "${BLUE}Настройка проброса порта $CODESERVER_PORT с хоста на namespace...${NC}"
    
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
        echo -e "${GREEN}tun0 найден внутри $VPN_NS — добавляем MASQUERADE внутри namespace (по интерфейсу tun0)${NC}"
        # если нет iptables в ns — ip netns exec вызовет системный iptables; обычно доступно
        ip netns exec "$VPN_NS" iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
    else
        echo -e "${YELLOW}tun0 не найден внутри $VPN_NS — ставим резервный MASQUERADE на хосте только для подсети $VETH_SUBNET${NC}"
        iptables -t nat -A POSTROUTING -s "${VETH_SUBNET}" -j MASQUERADE
    fi
    
    # FORWARD: разрешаем трафик между хостом и подсетью veth
    # Это необходимо, так как политика FORWARD может быть DROP (например, из-за ufw/docker)
    echo -e "${BLUE}Настройка правил iptables FORWARD для подсети veth...${NC}"
    
    # Разрешаем связанные/установленные соединения
    iptables -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    
    # Разрешаем трафик из подсети veth (в обе стороны)
    iptables -I FORWARD 1 -s "${VETH_SUBNET}" -j ACCEPT
    iptables -I FORWARD 1 -d "${VETH_SUBNET}" -j ACCEPT
    
    echo -e "${GREEN}✓ Правила FORWARD настроены${NC}"
    echo -e "${GREEN}✓ Проброс порта настроен${NC}"
    echo -e "${GREEN}  Хост: 10.200.1.1:$CODESERVER_PORT → Namespace: 10.200.1.2:$CODESERVER_PORT${NC}"
    echo ""
else
    echo -e "${GREEN}✓ Проброс порта уже настроен${NC}"
    echo ""
fi

# Создание директории для code-server
mkdir -p "$CODESERVER_DIR"

# Получаем текущего пользователя
CURRENT_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-root}")

# Определяем хост для прокси
# Если tinyproxy/HTTP proxy запускается на хосте и слушает на 127.0.0.1:1090,
# то внутри namespace 127.0.0.1 это loopback namespace — не тот. Если proxy запущен на хосте,
# используйте вместо 127.0.0.1 IP хоста в veth-сети: 10.200.1.1
# Здесь мы пробуем автоматически:
PROXY_HOST="127.0.0.1:1090"
# если tinyproxy слушает на хосте по 0.0.0.0:1090 — лучше использовать 10.200.1.1
# проверяем на хосте:
if ss -tlnp | grep -q ':1090'; then
    # но внутри namespace 127.0.0.1 может не работать; используем адрес veth-хоста
    PROXY_HOST="10.200.1.1:1090"
fi

echo -e "${BLUE}Запуск code-server...${NC}"
echo -e "${BLUE}  Порт: $CODESERVER_PORT${NC}"
echo -e "${BLUE}  Директория: $CODESERVER_DIR${NC}"
echo -e "${BLUE}  Network Namespace: $VPN_NS${NC}"
echo -e "${BLUE}  Доступ: http://$(hostname -I | awk "{print \$1}"):$CODESERVER_PORT${NC}"
echo -e "${BLUE}  Proxy: $PROXY_HOST${NC}"
echo -e "${YELLOW}  Пароль будет в ~/.config/code-server/config.yaml${NC}"
echo ""

# Запуск code-server в namespace с правами пользователя
# code-server будет использовать HTTP прокси (порт 1090) для всех запросов
# Это соответствует настройкам из runbook_vpn_setup.md
ip netns exec "$VPN_NS" sudo -u "$CURRENT_USER" bash -c "
    # Устанавливаем переменные окружения для прокси
    export http_proxy=http://$PROXY_HOST
    export https_proxy=http://$PROXY_HOST
    export HTTP_PROXY=http://$PROXY_HOST
    export HTTPS_PROXY=http://$PROXY_HOST
    
    # Запускаем code-server
    exec code-server --bind-addr 0.0.0.0:$CODESERVER_PORT --auth password --disable-telemetry --user-data-dir \"$CODESERVER_DIR\"
"

# exit -> cleanup via trap (никогда не достигнется, так как code-server запускается с exec)
