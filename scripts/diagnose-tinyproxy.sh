#!/usr/bin/env bash
set -e

echo "=========================================="
echo "Диагностика tinyproxy"
echo "=========================================="
echo ""

# 1. Проверка процесса tinyproxy
echo "[1/8] Проверка процесса tinyproxy..."
if docker exec vpn pgrep -x tinyproxy >/dev/null 2>&1; then
    TINY_PID=$(docker exec vpn pgrep -x tinyproxy)
    echo "✓ Процесс tinyproxy запущен (PID: $TINY_PID)"
    echo "   Команда: $(docker exec vpn ps aux | grep tinyproxy | awk '{print $11}')"
else
    echo "✗ Процесс tinyproxy не запущен"
fi
echo ""

# 2. Проверка порта 1090
echo "[2/8] Проверка порта 1090..."
if docker exec vpn netstat -tlnp 2>/dev/null | grep -q ":1090 "; then
    echo "✓ Порт 1090 слушается"
    echo "   Процесс: $(docker exec vpn netstat -tlnp 2>/dev/null | grep ":1090 " | awk '{print $7}')"
else
    echo "✗ Порт 1090 не слушается"
fi
echo ""

# 3. Проверка конфигурации
echo "[3/8] Проверка конфигурации..."
echo "   User: $(docker exec vpn grep "^User" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Group: $(docker exec vpn grep "^Group" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Listen: $(docker exec vpn grep "^Listen" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo "   Port: $(docker exec vpn grep "^Port" /etc/tinyproxy/tinyproxy.conf | awk '{print $2}')"
echo ""

# 4. Проверка лог файла
echo "[4/8] Проверка лог файла..."
if docker exec vpn test -f /var/log/tinyproxy/tinyproxy.log 2>/dev/null; then
    echo "✓ Лог файл существует"
    echo "   Размер: $(docker exec vpn wc -l /var/log/tinyproxy/tinyproxy.log) строк"
    echo "   Последние 5 строк:"
    docker exec vpn tail -5 /var/log/tinyproxy/tinyproxy.log | sed 's/^/   /'
else
    echo "✗ Лог файл не существует"
fi
echo ""

# 5. Проверка PID файла
echo "[5/8] Проверка PID файла..."
if docker exec vpn test -f /var/run/tinyproxy.pid 2>/dev/null; then
    echo "✓ PID файл существует"
    echo "   Содержимое: $(docker exec vpn cat /var/run/tinyproxy/tinyproxy.pid)"
else
    echo "✗ PID файл не существует"
fi
echo ""

# 6. Проверка прав на порт
echo "[6/8] Проверка прав на порт..."
if docker exec vpn netstat -tlnp 2>/dev/null | grep ":1090 " | awk '{print $4}' | grep -q "LISTEN"; then
    echo "✓ Права LISTEN на порту"
else
    echo "✗ Права LISTEN на порту"
fi
echo ""

# 7. Проверка прав на конфиг файл
echo "[7/8] Проверка прав на конфиг файл..."
if docker exec vpn test -r /etc/tinyproxy/tinyproxy.conf 2>/dev/null; then
    echo "✓ Конфиг файл доступен для чтения"
else
    echo "✗ Конфиг файл недоступен для чтения"
fi
echo ""

# 8. Попытка ручного запуска
echo "[8/8] Попытка ручного запуска..."
echo "   Остановка процесса (если запущен)..."
docker exec vpn pkill tinyproxy || true
sleep 1
echo "   Запуск tinyproxy с выводом в foreground..."
docker exec vpn tinyproxy -c /etc/tinyproxy/tinyproxy.conf &
sleep 2
echo "   Проверка процесса..."
if docker exec vpn pgrep -x tinyproxy >/dev/null 2>&1; then
    NEW_PID=$(docker exec vpn pgrep -x tinyproxy)
    echo "✓ Процесс запущен (PID: $NEW_PID)"
else
    echo "✗ Процесс не запущен"
fi
echo ""

# 9. Проверка порта после ручного запуска
echo "[9/8] Проверка порта после ручного запуска..."
sleep 2
if docker exec vpn netstat -tlnp 2>/dev/null | grep -q ":1090 "; then
    echo "✓ Порт 1090 слушается"
else
    echo "✗ Порт 1090 не слушается"
fi
echo ""

echo "=========================================="
echo "Диагностика завершена"
echo "=========================================="
