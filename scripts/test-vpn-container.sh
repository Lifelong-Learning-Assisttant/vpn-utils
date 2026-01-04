#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Тестирование VPN контейнера"
echo "=========================================="
echo ""

# Проверка, что контейнер запущен
echo "[1/6] Проверка статуса контейнера vpn..."
if docker ps --filter "name=vpn" --format "{{.Names}}" | grep -q "^vpn$"; then
    echo "✓ Контейнер vpn запущен"
else
    echo "✗ Контейнер vpn не запущен"
    echo "Запустите контейнер: cd vpn && docker compose up -d"
    exit 1
fi
echo ""

# Проверка наличия интерфейса tun0
echo "[2/6] Проверка интерфейса tun0..."
if docker exec vpn ip link show tun0 >/dev/null 2>&1; then
    echo "✓ Интерфейс tun0 найден"
    docker exec vpn ip addr show tun0 | grep inet | awk '{print "  IP адрес: " $2}'
else
    echo "✗ Интерфейс tun0 не найден"
    echo "Подключитесь к VPN: docker exec -it vpn bash"
    echo "  adguardvpn-cli login"
    echo "  adguardvpn-cli connect -l <location>"
    exit 1
fi
echo ""

# Проверка запуска dnsmasq
echo "[3/6] Проверка dnsmasq..."
if docker exec vpn pgrep -x dnsmasq >/dev/null; then
    echo "✓ dnsmasq запущен (PID: $(docker exec vpn pgrep -x dnsmasq))"
else
    echo "✗ dnsmasq не запущен"
    echo "Запустите прокси сервисы: docker exec -it vpn /usr/local/bin/start-vpn.sh"
fi
echo ""

# Проверка запуска danted
echo "[4/6] Проверка danted (SOCKS5 proxy)..."
if docker exec vpn pgrep -x danted >/dev/null; then
    echo "✓ danted запущен (PID: $(docker exec vpn pgrep -x danted))"
else
    echo "✗ danted не запущен"
    echo "Запустите прокси сервисы: docker exec -it vpn /usr/local/bin/start-vpn.sh"
fi
echo ""

# Проверка запуска tinyproxy
echo "[5/6] Проверка tinyproxy (HTTP proxy)..."
if docker exec vpn pgrep -x tinyproxy >/dev/null; then
    echo "✓ tinyproxy запущен (PID: $(docker exec vpn pgrep -x tinyproxy))"
else
    echo "✗ tinyproxy не запущен"
    echo "Запустите прокси сервисы: docker exec -it vpn /usr/local/bin/start-vpn.sh"
fi
echo ""

# Проверка IP через VPN
echo "[6/6] Проверка IP через VPN..."
if docker exec vpn curl -s --connect-timeout 5 https://api.ipify.org >/dev/null 2>&1; then
    IP=$(docker exec vpn curl -s https://api.ipify.org)
    echo "✓ IP через VPN: $IP"
else
    echo "✗ Не удалось получить IP через VPN"
fi
echo ""

echo "=========================================="
echo "Тестирование завершено"
echo "=========================================="
