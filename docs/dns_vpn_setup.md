# Быстрый старт: VPN + DNS

## Цель

Иметь рабочую конфигурацию, где:
- ✅ Весь трафик идет через VPN
- ✅ SSH всегда доступен
- ✅ Kilo Code и нейросети работают

---

## 1. Подключение VPN

```bash
# Подключить VPN к Германии
adguardvpn-cli connect -l FRANKFURT

# Включить автоматическую смену DNS
adguardvpn-cli config set-change-system-dns on

# Проверить статус
adguardvpn-cli status
```

## 2. Проверка работы

```bash
# Проверить IP (должен показать VPN IP)
curl ifconfig.me

# Проверить DNS
dig google.com +short

# Перезапустите VS Code
```

## 3. Отключение VPN

```bash
# Отключить VPN
adguardvpn-cli disconnect

# Проверить DNS
dig google.com +short
```

---

## Диагностика сети

### Полная диагностика (одной командой)
```bash
echo "=== ДИАГНОСТИКА СЕТИ ===" && echo "" && echo "1. VPN статус:" && adguardvpn-cli status && echo "" && echo "2. Настройки VPN:" && adguardvpn-cli config show | grep -E "DNS|system" && echo "" && echo "3. DNS (resolvectl):" && resolvectl status | grep -A5 "Link 1281 (tun0)" && echo "" && echo "4. IP адрес:" && curl -s ifconfig.me && echo "" && echo "5. Маршруты по умолчанию:" && ip route show | grep default && echo "" && echo "6. Policy routing:" && ip rule show | grep "176.123.161.187" && echo "" && echo "7. Маршруты для SSH (table 100):" && ip route show table 100 && echo "" && echo "8. Маршруты VPN (table 880):" && ip route show table 880 | head -3 && echo "..." && ip route show table 880 | tail -3 && echo "" && echo "9. Проверка DNS:" && dig google.com +short | head -1 && echo "" && echo "10. Проверка порта 53:" && ss -ltpn | grep 53
```

### Базовые проверки
```bash
# DNS
resolvectl status
cat /etc/resolv.conf

# VPN
adguardvpn-cli status
adguardvpn-cli config show

# Маршруты
ip route show
ip rule show
ip route show table 100  # SSH
ip route show table 880  # VPN
```


## Troubleshooting

### Kilo Code не работает
```bash
# 1. Отключить VPN
adguardvpn-cli disconnect

# 2. Включить смену DNS
adguardvpn-cli config set-change-system-dns on

# 3. Подключить снова
adguardvpn-cli connect -l FRANKFURT

# 4. Перезапустить VS Code
```

### Apt не работает
```bash
# Проверить DNS
dig google.com +short

# Перезапустить systemd-resolved
sudo systemctl restart systemd-resolved
```

### SSH отключается
```bash
# Проверить policy routing
ip rule show
# Должно быть: from 176.123.161.187 lookup 100
```

---

## Как это работает

### Схема
```
Весь трафик → VPN (tun0) → Франкфурт
SSH → Прямой доступ (table 100)
DNS → Автоматически через VPN
```

### Ключевые моменты
1. **`set-change-system-dns on`** — автоматически меняет DNS
2. **Policy routing** — SSH защищен от VPN
3. **Table 880** — весь трафик через VPN
4. **Table 100** — SSH трафик напрямую

---

## См. также
- [Архитектура сети](network_architecture.md) — теория и схемы
- [Справочник команд](adguard_vpn_setup.md) — все команды и скрипты
- [Базовые настройки DNS](dns_base.md) — восстановление базового DNS

---

**Дата:** 2025-12-29 | **Статус:** ✅ Рабочая конфигурация