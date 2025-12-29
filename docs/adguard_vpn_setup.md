# Справочник команд AdGuard VPN CLI

## Установка

```bash
wget https://cdn.adguard-vpn.com/cli/adguardvpn-cli_1.0.0_amd64.deb
sudo dpkg -i adguardvpn-cli_1.0.0_amd64.deb
adguardvpn-cli --version
```

## Команды управления

### Подключение/отключение
```bash
adguardvpn-cli connect -l FRANKFURT    # Подключить
adguardvpn-cli disconnect              # Отключить
adguardvpn-cli toggle                  # Переключить
adguardvpn-cli status                  # Статус
```

### Настройки
```bash
adguardvpn-cli config show             # Все настройки
adguardvpn-cli config set-change-system-dns on   # Авто-DNS
adguardvpn-cli config set-change-system-dns off  # Ручной DNS
```

### Информация
```bash
adguardvpn-cli locations               # Список серверов
adguardvpn-cli account                 # Аккаунт
```

## Скрипты для автоматизации

### vpn-connect.sh
```bash
#!/bin/bash
adguardvpn-cli connect -l FRANKFURT
adguardvpn-cli config set-change-system-dns on
echo "VPN подключен. IP: $(curl -s ifconfig.me)"
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

## Диагностика

```bash
# Полная диагностика
echo "=== ADGUARD VPN DIAGNOSTICS ===" && echo "" && echo "1. Status:" && adguardvpn-cli status && echo "" && echo "2. Config:" && adguardvpn-cli config show && echo "" && echo "3. IP:" && curl -s ifconfig.me && echo "" && echo "4. DNS:" && dig google.com +short | head -1 && echo "" && echo "5. Routes:" && ip route show | grep -E "default|tun0" && echo "" && echo "6. Policy:" && ip rule show | grep -E "176.123|880"
```

## Troubleshooting

### VPN подключен, но интернет не работает
```bash
sudo systemctl restart systemd-resolved
```

### Kilo Code не работает
```bash
adguardvpn-cli disconnect
adguardvpn-cli config set-change-system-dns on
adguardvpn-cli connect -l FRANKFURT
```

### Apt не работает
```bash
dig google.com +short
sudo systemctl restart systemd-resolved
```

## Удаление

```bash
sudo dpkg -r adguardvpn-cli
sudo rm -rf ~/.local/share/adguardvpn-cli
```

---

**Дата:** 2025-12-29 | **Статус:** ✅ Справочник команд
