#!/bin/bash
# Скрипт для split routing: OpenAI/OpenRouter через VPN, остальное напрямую
# НЕ ТРОГАЕТ SSH правило (table 100)

# Проверка VPN шлюза (AdGuard VPN не создает default route через tun0)
# Используем шлюз из таблицы 880 или определяем по интерфейсу
VPN_GW="10.255.255.1"  # Стандартный шлюз AdGuard VPN
if ! ip route show table 880 | grep -q "default via"; then
    echo "⚠️  Table 880 пустая, создаем маршрут..."
    # Проверяем есть ли tun0
    if ! ip addr show tun0 &>/dev/null; then
        echo "❌ VPN интерфейс tun0 не найден!"
        exit 1
    fi
fi

# IP вашего сервера
SERVER_IP="176.123.161.187"

# Cloudflare диапазоны (OpenAI)
CLOUDFLARE_RANGES=(
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
)

# OpenRouter IP-диапазоны (отдельно)
OPENROUTER_RANGES=(
    "8.6.112.0/24"
    "8.47.69.0/24"
)

echo "=== Настройка split routing (безопасная) ==="
echo "VPN Gateway: $VPN_GW"
echo "Server IP: $SERVER_IP"
echo ""

# 1. Очистка старых правил для Cloudflare (НЕ трогаем table 100!)
echo "Очистка старых Cloudflare правил..."
for range in "${CLOUDFLARE_RANGES[@]}"; do
    ip rule del from $SERVER_IP to $range table 880 2>/dev/null || true
done

# 2. Добавление маршрутов в table 880
echo "Добавление маршрутов в table 880..."
ip route flush table 880 2>/dev/null || true
# Добавляем маршруты для Cloudflare диапазонов через tun0
for range in "${CLOUDFLARE_RANGES[@]}"; do
    ip route add $range dev tun0 table 880 2>/dev/null || true
done
# Добавляем маршруты для OpenRouter через tun0
for range in "${OPENROUTER_RANGES[@]}"; do
    ip route add $range dev tun0 table 880 2>/dev/null || true
done

# 3. Добавление правил для Cloudflare и OpenRouter
echo "Добавление правил для Cloudflare и OpenRouter..."
for range in "${CLOUDFLARE_RANGES[@]}"; do
    ip rule add from $SERVER_IP to $range table 880
done
for range in "${OPENROUTER_RANGES[@]}"; do
    ip rule add from $SERVER_IP to $range table 880
done

# 4. Проверка
echo ""
echo "=== Проверка ==="
echo "✅ SSH правило (table 100) сохранено:"
ip rule show | grep "176.123.161.187"
ip route show table 100
echo ""
echo "✅ Cloudflare правила (table 880):"
ip rule show | grep "880" | head -3
echo "..."
ip route show table 880
echo ""
echo "✅ Готово! OpenAI/OpenRouter → VPN, остальное → провайдер, SSH → провайдер"