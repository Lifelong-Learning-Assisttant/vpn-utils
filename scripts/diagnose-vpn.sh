#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Диагностика VPN контейнера"
echo "=========================================="
echo ""

# 1. Проверка статуса контейнера
echo "[1/6] Проверка статуса контейнера vpn..."
if docker ps --filter "name=vpn" --format "{{.Names}}" | grep -q "^vpn$"; then
    echo "✓ Контейнер vpn запущен"
    echo "   Статус: $(docker ps --filter "name=vpn" --format "{{.Status}}")"
else
    echo "✗ Контейнер vpn не запущен"
    exit 1
fi
echo ""

# 2. Проверка интерфейса tun0
echo "[2/6] Проверка интерфейса tun0..."
if docker exec vpn ip link show tun0 >/dev/null 2>&1; then
    echo "✓ Интерфейс tun0 найден"
    docker exec vpn ip addr show tun0 | grep inet | awk '{print "   IP адрес: " $2}'
else
    echo "✗ Интерфейс tun0 не найден"
    echo "   Подключитесь к VPN: docker exec -it vpn bash"
    echo "   adguardvpn-cli connect -l <location>"
fi
echo ""

# 3. Проверка запущенных процессов
echo "[3/6] Проверка запущенных процессов..."
echo "   dnsmasq:"
if docker exec vpn pgrep -x dnsmasq >/dev/null 2>&1; then
    echo "   ✓ Запущен (PID: $(docker exec vpn pgrep -x dnsmasq))"
else
    echo "   ✗ Не запущен"
fi

echo "   danted:"
if docker exec vpn pgrep -x danted >/dev/null 2>&1; then
    echo "   ✓ Запущен (PID: $(docker exec vpn pgrep -x danted))"
else
    echo "   ✗ Не запущен"
fi

echo "   tinyproxy:"
if docker exec vpn pgrep -x tinyproxy >/dev/null 2>&1; then
    echo "   ✓ Запущен (PID: $(docker exec vpn pgrep -x tinyproxy))"
else
    echo "   ✗ Не запущен"
fi
echo ""

# 4. Проверка портов
echo "[4/6] Проверка портов..."
echo "   Порт 1080 (SOCKS5):"
if docker exec vpn netstat -tlnp 2>/dev/null | grep -q ":1080 "; then
    echo "   ✓ Порт слушается"
else
    echo "   ✗ Порт не слушается"
fi

echo "   Порт 1090 (HTTP):"
if docker exec vpn netstat -tlnp 2>/dev/null | grep -q ":1090 "; then
    echo "   ✓ Порт слушается"
else
    echo "   ✗ Порт не слушается"
fi
echo ""

# 5. Проверка логов tinyproxy
echo "[5/6] Проверка логов tinyproxy..."
if docker exec vpn test -f /var/log/tinyproxy/tinyproxy.log 2>/dev/null; then
    echo "✓ Лог файл существует"
    echo "   Последние 10 строк:"
    docker exec vpn tail -10 /var/log/tinyproxy/tinyproxy.log | sed 's/^/   /'
else
    echo "✗ Лог файл не существует"
fi
echo ""

# 6. Проверка конфигурации tinyproxy
echo "[6/6] Проверка конфигурации tinyproxy..."
echo "   User: $(docker exec vpn grep "^User" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Group: $(docker exec vpn grep "^Group" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Listen: $(docker exec vpn grep "^Listen" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Port: $(docker exec vpn grep "^Port" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo ""

# 7. Тестирование прокси
echo "[7/6] Тестирование прокси..."
echo "   Тест HTTP proxy (порт 1090):"
if docker exec vpn curl -s --connect-timeout 5 --proxy http://127.0.0.1:1090 https://api.ipify.org >/dev/null 2>&1; then
    IP=$(docker exec vpn curl -s --proxy http://127.0.0.1:1090 https://api.ipify.org)
    echo "   ✓ Успешно! IP через прокси: $IP"
else
    echo "   ✗ Не удалось подключиться"
fi

echo ""
echo "   Тест SOCKS5 proxy (порт 1080):"
if docker exec vpn curl -s --connect-timeout 5 --socks5 127.0.0.1:1080 https://api.ipify.org >/dev/null 2>&1; then
    IP=$(docker exec vpn curl -s --socks5 127.0.0.1:1080 https://api.ipify.org)
    echo "   ✓ Успешно! IP через прокси: $IP"
else
    echo "   ✗ Не удалось подключиться"
fi
echo ""

echo "=========================================="
echo "Диагностика завершена"
echo "=========================================="
