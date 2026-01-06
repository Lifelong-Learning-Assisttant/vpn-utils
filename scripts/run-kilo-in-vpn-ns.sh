#!/bin/bash
# Скрипт для запуска Kilo CLI в network namespace vpn-ns с VPN

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VPN_NS="vpn-ns"

echo -e "${GREEN}=== Запуск Kilo CLI в network namespace $VPN_NS с VPN ===${NC}"
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
    echo -e "${YELLOW}⚠️  VPN не подключен (интерфейс tun0 не найден)${NC}"
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

# Получаем текущего пользователя
CURRENT_USER=$(logname || echo $SUDO_USER)

# Получаем домашнюю директорию пользователя
USER_HOME=$(eval echo ~$CURRENT_USER)
KILO_PATH="$USER_HOME/.npm-global/bin/kilo"

# Проверка Kilo CLI
if [ ! -f "$KILO_PATH" ]; then
    echo -e "${RED}Kilo CLI не установлен${NC}"
    echo -e "${YELLOW}Установите его:${NC}"
    echo "  mkdir -p ~/.npm-global"
    echo "  npm config set prefix '~/.npm-global'"
    echo "  echo 'export PATH=~/.npm-global/bin:\$PATH' >> ~/.bashrc"
    echo "  source ~/.bashrc"
    echo "  npm install -g @kilocode/cli"
    exit 1
fi

# Проверка версии Kilo CLI
KILO_VERSION=$("$KILO_PATH" --version 2>/dev/null || echo "unknown")
echo -e "${GREEN}✓ Kilo CLI установлен${NC}"
echo -e "${GREEN}  Версия: $KILO_VERSION${NC}"
echo -e "${GREEN}  Путь: $KILO_PATH${NC}"
echo ""

# Проверка рабочей директории
if [ ! -d "." ]; then
    echo -e "${RED}Рабочая директория не найдена${NC}"
    exit 1
fi

echo -e "${BLUE}Запуск Kilo CLI...${NC}"
echo ""

# Запуск Kilo CLI в namespace с правами пользователя и правильным PATH
ip netns exec "$VPN_NS" sudo -u "$CURRENT_USER" env PATH="$USER_HOME/.npm-global/bin:$PATH" "$KILO_PATH" "$@"

echo ""
echo -e "${GREEN}=== Kilo CLI завершил работу ===${NC}"
