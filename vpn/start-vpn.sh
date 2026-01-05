#!/bin/bash
set -e

echo "[start-vpn.sh] Запуск прокси сервисов..."
echo ""

# 1) Проверяем, что VPN подключен
echo "[start-vpn.sh] Проверка VPN соединения..."
if ! ip link show tun0 >/dev/null 2>&1; then
    echo "[start-vpn.sh] ОШИБКА: Интерфейс tun0 не найден!"
    echo "[start-vpn.sh] Пожалуйста, сначала подключитесь к VPN:"
    echo "   adguardvpn-cli connect -l <location>"
    exit 1
fi

echo "[start-vpn.sh] Интерфейс tun0 найден:"
ip addr show tun0 | grep inet
echo ""

# 2) Запускаем dnsmasq (локальный резолвер)
echo "[start-vpn.sh] Запуск dnsmasq..."
if [ -f /etc/dnsmasq.conf ]; then
    pkill dnsmasq || true
    dnsmasq --conf-file=/etc/dnsmasq.conf --user=root --group=root &
    echo "[start-vpn.sh] dnsmasq запущен"
else
    echo "[start-vpn.sh] Конфиг dnsmasq не найден"
fi
echo ""

# 3) Запускаем danted (SOCKS5 proxy на порту 1080)
echo "[start-vpn.sh] Запуск danted (SOCKS5 proxy :1080)..."
if [ -f /etc/danted.conf ]; then
    pkill danted || true
    /usr/sbin/danted -f /etc/danted.conf &
    echo "[start-vpn.sh] danted запущен"
else
    echo "[start-vpn.sh] Конфиг danted не найден"
fi
echo ""

# 4) Запускаем tinyproxy (HTTP proxy на порту 1090)
echo "[start-vpn.sh] Запуск tinyproxy (HTTP proxy :1090)..."
if [ -f /etc/tinyproxy/tinyproxy.conf ]; then
    pkill tinyproxy || true
    tinyproxy -c /etc/tinyproxy/tinyproxy.conf &
    echo "[start-vpn.sh] tinyproxy запущен"
else
    echo "[start-vpn.sh] Конфиг tinyproxy не найден"
fi
echo ""

# 5) Проверяем, что сервисы запустились
echo "[start-vpn.sh] Проверка запущенных сервисов..."
sleep 2

if pgrep -x danted >/dev/null; then
    echo "[start-vpn.sh] ✓ danted запущен (PID: $(pgrep -x danted))"
else
    echo "[start-vpn.sh] ✗ danted не запущен"
fi

if pgrep -x tinyproxy >/dev/null; then
    echo "[start-vpn.sh] ✓ tinyproxy запущен (PID: $(pgrep -x tinyproxy))"
else
    echo "[start-vpn.sh] ✗ tinyproxy не запущен"
fi

if pgrep -x dnsmasq >/dev/null; then
    echo "[start-vpn.sh] ✓ dnsmasq запущен (PID: $(pgrep -x dnsmasq))"
else
    echo "[start-vpn.sh] ✗ dnsmasq не запущен"
fi

echo ""
echo "=========================================="
echo "[start-vpn.sh] Все прокси сервисы запущены!"
echo "=========================================="
echo "SOCKS5 proxy: 127.0.0.1:1080"
echo "HTTP proxy:   127.0.0.1:1090"
echo "=========================================="
echo ""
echo "Для просмотра логов:"
echo "  tail -f /var/log/danted.log"
echo "  tail -f /var/log/tinyproxy/tinyproxy.log"
echo ""
