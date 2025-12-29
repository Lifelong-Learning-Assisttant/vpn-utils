#!/bin/bash
# Скрипт для тестирования split routing конфигурации

echo "=========================================="
echo "Тестирование split routing конфигурации"
echo "=========================================="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция проверки
check_route() {
    local target=$1
    local expected=$2
    local service=$3
    
    route=$(ip route get $target 2>/dev/null)
    
    if echo "$route" | grep -q "$expected"; then
        echo -e "${GREEN}✅${NC} $service: $target → $expected"
        return 0
    else
        echo -e "${RED}❌${NC} $service: $target → НЕПРАВИЛЬНО ($route)"
        return 1
    fi
}

# Функция проверки доступности
check_http() {
    local url=$1
    local service=$2
    
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 $url 2>/dev/null)
    
    if [[ "$status" =~ ^(200|401|403)$ ]]; then
        echo -e "${GREEN}✅${NC} $service: доступен (HTTP $status)"
        return 0
    else
        echo -e "${RED}❌${NC} $service: недоступен (HTTP $status)"
        return 1
    fi
}

echo "1. Проверка маршрутизации:"
echo "---------------------------"

# Проверяем маршруты
check_route "140.82.121.3" "dev enp3s0" "GitHub"
check_route "100.49.175.172" "dev enp3s0" "Docker Hub"
check_route "151.101.192.223" "dev enp3s0" "PyPI"
check_route "162.159.140.245" "dev tun0" "OpenAI"
check_route "8.6.112.6" "dev tun0" "OpenRouter"
check_route "176.123.161.187" "dev lo" "SSH (localhost)"

echo ""
echo "2. Проверка доступности сервисов:"
echo "----------------------------------"

# Проверяем доступность
check_http "https://api.github.com/user" "GitHub API"
check_http "https://registry.hub.docker.com/v2/" "Docker Hub"
check_http "https://pypi.org/pypi/requests/json" "PyPI"
check_http "https://api.openai.com/v1/models" "OpenAI API"
check_http "https://openrouter.ai/api/v1/models" "OpenRouter API"

echo ""
echo "3. Проверка VPN статуса:"
echo "------------------------"

# Проверка VPN
if adguardvpn-cli status | grep -q "Connected"; then
    echo -e "${GREEN}✅${NC} VPN подключен"
    adguardvpn-cli status | grep "Connected"
else
    echo -e "${RED}❌${NC} VPN отключен"
fi

echo ""
echo "4. Проверка policy routing:"
echo "---------------------------"

# Проверка правил
echo "Правило для SSH (table 100):"
ip rule show | grep "176.123.161.187" | grep "lookup 100" && echo -e "${GREEN}✅${NC} SSH правило активно" || echo -e "${RED}❌${NC} SSH правило отсутствует"

echo ""
echo "Правила для Cloudflare (table 880):"
count=$(ip rule show | grep "lookup 880" | wc -l)
if [ $count -ge 15 ]; then
    echo -e "${GREEN}✅${NC} Найдено $count правил (ожидается >=15)"
else
    echo -e "${YELLOW}⚠️${NC} Найдено $count правил (ожидается >=15)"
fi

echo ""
echo "5. Проверка маршрутов table 880:"
echo "--------------------------------"

# Проверка маршрутов в table 880
echo "Маршруты для Cloudflare:"
ip route show table 880 | grep -E "173.245|103.21|103.22|103.31|141.101|108.162|190.93|188.114|197.234|198.41|162.158|104.16|104.24|172.64|131.0" | head -3
echo "..."
ip route show table 880 | grep -E "8.6.112|8.47.69" && echo -e "${GREEN}✅${NC} OpenRouter маршруты есть" || echo -e "${RED}❌${NC} OpenRouter маршруты отсутствуют"

echo ""
echo "=========================================="
echo "Тестирование завершено"
echo "=========================================="