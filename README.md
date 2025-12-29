# VPN Utilities

Набор утилит и документации для настройки VPN в проекте.

## 🎯 Новая стратегия (2025-12-29)

**Рабочая конфигурация:**
1. **Базовые настройки** → `docs/dns_base.md` (systemd-resolved)
2. **VPN поверх базовых** → `docs/dns_vpn_setup.md` (AdGuard VPN со сменой DNS)

**Результат:** 

1. SSH с сервером сохраняется
2. Сервер доступен по своему публичному ip-адресу и сервисы по публичным портам тоже.
3. OpenRouter и OpenAI доступны через API запросы.
4. Kilo Code работает (вроде бы).

**Общий подход:** systemd-resolved + VPN DNS.


## 📚 Структура документации

### Быстрый старт
- **[docs/dns_vpn_setup.md](docs/dns_vpn_setup.md)** — Быстрый старт: команды, проверка, troubleshooting

### Теория и архитектура
- **[docs/network_architecture.md](docs/network_architecture.md)** — Как работает вся система (теория)

### Справочники
- **[docs/adguard_vpn_setup.md](docs/adguard_vpn_setup.md)** — Все команды AdGuard VPN и скрипты
- **[docs/dns_base.md](docs/dns_base.md)** — Базовые настройки DNS (восстановление)


## 🚀 Быстрый старт

```bash
# 1. Подключить VPN
adguardvpn-cli connect -l FRANKFURT

# 2. Включить авто-смену DNS
adguardvpn-cli config set-change-system-dns on

# 3. Проверить
curl ifconfig.me  # Должен показать VPN IP
```


## 🔍 Диагностика

```bash
# Полная диагностика сети
echo "=== ДИАГНОСТИКА СЕТИ ===" && echo "" && echo "1. VPN статус:" && adguardvpn-cli status && echo "" && echo "2. Настройки VPN:" && adguardvpn-cli config show | grep -E "DNS|system" && echo "" && echo "3. DNS (resolvectl):" && resolvectl status | grep -A5 "Link 1281 (tun0)" && echo "" && echo "4. IP адрес:" && curl -s ifconfig.me && echo "" && echo "5. Маршруты по умолчанию:" && ip route show | grep default && echo "" && echo "6. Policy routing:" && ip rule show | grep "176.123.161.187" && echo "" && echo "7. Маршруты для SSH (table 100):" && ip route show table 100 && echo "" && echo "8. Маршруты VPN (table 880):" && ip route show table 880 | head -3 && echo "..." && ip route show table 880 | tail -3 && echo "" && echo "9. Проверка DNS:" && dig google.com +short | head -1 && echo "" && echo "10. Проверка порта 53:" && ss -ltpn | grep 53
```

## 🛠️ Troubleshooting

### Kilo Code не работает
```bash
adguardvpn-cli disconnect
adguardvpn-cli config set-change-system-dns on
adguardvpn-cli connect -l FRANKFURT
# Перезапустить VS Code
```

### Apt не работает
```bash
sudo systemctl restart systemd-resolved
```

### SSH отключается
```bash
ip rule show  # Должно быть: from 176.123.161.187 lookup 100
```

## 📖 Дополнительно

- **Версия документации:** 2025-12-29
- **Статус:** ✅ Рабочая конфигурация подтверждена
- **Тип трафика:** Весь трафик через VPN (кроме SSH)