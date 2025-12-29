# Справочник команд AdGuard VPN CLI

## Установка

```bash
wget https://cdn.adguard-vpn.com/cli/adguardvpn-cli_1.0.0_amd64.deb
sudo dpkg -i adguardvpn-cli_1.0.0_amd64.deb
adguardvpn-cli --version
```

---

## Команды управления

### Подключение/отключение
```bash
adguardvpn-cli connect -l FRANKFURT    # Подключить к Германии
adguardvpn-cli disconnect              # Отключить
adguardvpn-cli toggle                  # Переключить
adguardvpn-cli status                  # Статус
```

### Настройки
```bash
adguardvpn-cli config show             # Все настройки
adguardvpn-cli config set-change-system-dns on   # Авто-DNS (для полного VPN)
adguardvpn-cli config set-change-system-dns off  # Ручной DNS (для split routing)
```

### Информация
```bash
adguardvpn-cli locations               # Список серверов
adguardvpn-cli account                 # Аккаунт
```

---

## Скрипты для автоматизации

### vpn-connect-split.sh (для split routing)
```bash
#!/bin/bash
# Подключение VPN + split routing

echo "=== Подключение VPN ==="
adguardvpn-cli connect -l FRANKFURT

echo "=== Отключение авто-DNS ==="
adguardvpn-cli config set-change-system-dns off

echo "=== Настройка split routing ==="
sudo /home/llm-dev/project/lifelong_learning_assistant/vpn-utils/setup_split_routing.sh

echo "=== Проверка ==="
/home/llm-dev/project/lifelong_learning_assistant/vpn-utils/test_split_routing.sh
```

### vpn-connect-full.sh (для полного VPN)
```bash
#!/bin/bash
# Подключение полного VPN (весь трафик через VPN)

echo "=== Подключение VPN ==="
adguardvpn-cli connect -l FRANKFURT

echo "=== Включение авто-DNS ==="
adguardvpn-cli config set-change-system-dns on

echo "=== Проверка IP ==="
curl ifconfig.me
```

### vpn-disconnect.sh
```bash
#!/bin/bash
adguardvpn-cli disconnect
echo "VPN отключен"
```

### vpn-status.sh
```bash
#!/bin/bash
STATUS=$(adguardvpn-cli status | grep "Connected")
if [ -n "$STATUS" ]; then
    echo "✅ VPN: $(echo $STATUS | cut -d' ' -f3)"
    echo "🌐 IP: $(curl -s ifconfig.me)"
    echo "🔧 DNS: $(resolvectl status | grep "Current DNS Server" | head -1 | awk '{print $4}')"
else
    echo "❌ VPN: Отключен"
fi
```

---

## Диагностика

### Полная диагностика
```bash
echo "=== ADGUARD VPN DIAGNOSTICS ===" && echo "" && echo "1. Status:" && adguardvpn-cli status && echo "" && echo "2. Config:" && adguardvpn-cli config show && echo "" && echo "3. IP:" && curl -s ifconfig.me && echo "" && echo "4. DNS:" && dig google.com +short | head -1 && echo "" && echo "5. Routes:" && ip route show | grep -E "default|tun0" && echo "" && echo "6. Policy:" && ip rule show | grep -E "176.123|880"
```

### Базовые проверки
```bash
# VPN статус
adguardvpn-cli status

# Настройки
adguardvpn-cli config show

# IP
curl ifconfig.me

# DNS
dig google.com +short

# Маршруты
ip route show | grep default

# Policy routing
ip rule show
```

---

## Troubleshooting

### VPN подключен, но интернет не работает
```bash
sudo systemctl restart systemd-resolved
```

### Kilo Code не работает (при полном VPN)
```bash
adguardvpn-cli disconnect
adguardvpn-cli config set-change-system-dns on
adguardvpn-cli connect -l FRANKFURT
# Перезапустить VS Code
```

### Apt не работает
```bash
dig google.com +short
sudo systemctl restart systemd-resolved
```

### Split routing не работает
```bash
# 1. Проверить VPN
adguardvpn-cli status

# 2. Перезапустить split routing
sudo ./setup_split_routing.sh

# 3. Проверить тестами
./test_split_routing.sh
```

---

## Удаление

```bash
sudo dpkg -r adguardvpn-cli
sudo rm -rf ~/.local/share/adguardvpn-cli
```

---

## Режимы работы

### Режим 1: Split Routing (рекомендуется)
```bash
adguardvpn-cli connect -l FRANKFURT
adguardvpn-cli config set-change-system-dns off
sudo ./setup_split_routing.sh
```
**Для:** OpenAI/OpenRouter через VPN, остальное напрямую

### Режим 2: Full VPN
```bash
adguardvpn-cli connect -l FRANKFURT
adguardvpn-cli config set-change-system-dns on
```
**Для:** Весь трафик через VPN

---

**Дата:** 2025-12-29  
**Статус:** ✅ Справочник команд
