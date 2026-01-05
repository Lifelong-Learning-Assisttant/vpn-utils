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

# Проверка IP без VPN
echo "[6a/7] Проверка IP без VPN..."
IP_WITHOUT_VPN=$(curl -s --connect-timeout 5 https://api.ipify.org 2>/dev/null)
if [ -n "$IP_WITHOUT_VPN" ]; then
    echo "✓ IP без VPN: $IP_WITHOUT_VPN"
else
    echo "✗ Не удалось получить IP без VPN"
fi
echo ""

# Проверка IP через HTTP proxy
echo "[6b/7] Проверка IP через HTTP proxy..."
if docker exec vpn curl -s --connect-timeout 5 --proxy http://127.0.0.1:1090 https://api.ipify.org >/dev/null 2>&1; then
    IP_HTTP=$(docker exec vpn curl -s --proxy http://127.0.0.1:1090 https://api.ipify.org)
    echo "✓ IP через HTTP proxy: $IP_HTTP"
else
    echo "✗ Не удалось получить IP через HTTP proxy"
fi
echo ""

# Проверка IP через SOCKS5 proxy
echo "[6c/7] Проверка IP через SOCKS5 proxy..."
if docker exec vpn curl -s --connect-timeout 5 --socks5 127.0.0.1:1080 https://api.ipify.org >/dev/null 2>&1; then
    IP_SOCKS5=$(docker exec vpn curl -s --socks5 127.0.0.1:1080 https://api.ipify.org)
    echo "✓ IP через SOCKS5 proxy: $IP_SOCKS5"
else
    echo "✗ Не удалось получить IP через SOCKS5 proxy"
fi
echo ""

# Сравнение IP адресов
echo "[6d/7] Сравнение IP адресов..."
if [ "$IP_WITHOUT_VPN" != "$IP_HTTP" ] || [ "$IP_WITHOUT_VPN" != "$IP_SOCKS5" ]; then
    echo "✓ IP адрес изменился через VPN"
else
    echo "✗ IP адрес не изменился"
fi
echo ""

# Тестирование доступа к Google Gemini через VPN
echo "[7a/8] Тестирование доступа к Google Gemini через VPN..."
if docker exec vpn bash -c "source /vpn-config/.env && curl -s --proxy http://127.0.0.1:1090 -H 'x-goog-api-key: \$GOOGLE_GEMINI_API_KEY' -H 'Content-Type: application/json' -d '{\"contents\":[{\"parts\":[{\"text\":\"Hello from VPN!\"}]}]}' https://generativelanguage.googleapis.com/v1beta/models/google/gemini-3-flash-preview:generateContent" >/dev/null 2>&1; then
    echo "✓ Доступ к Google Gemini через VPN работает"
else
    echo "✗ Не удалось получить доступ к Google Gemini через VPN"
fi
echo ""

echo "=========================================="
echo "Тестирование завершено"
echo "=========================================="
