# Настройка DNS и VPN на Ubuntu 22.04 (Cloud.ru)

## Цель

Иметь рабочую конфигурацию, где:
- ✅ SSH всегда доступен (даже с включенным VPN)
- ✅ Локальный DNS работает (без VPN)
- ✅ Весь трафик идет через VPN (кроме SSH)
- ✅ Docker контейнеры работают через VPN
- ✅ Kilo Code и нейросети работают

---

## Проблема

Kilo Code не работает, потому что:
- Локальный DNS (systemd-resolved) резолвит через провайдера
- AdGuard VPN не меняет системный DNS
- Kilo Code использует системный DNS и не может подключиться к нейросетям

---

## Решение: Переключение на VPN DNS

### Шаг 1: Подключить VPN
```bash
adguardvpn-cli connect -l FRANKFURT
```

### Шаг 2: Проверить что VPN подключен
```bash
adguardvpn-cli status
# Должно показать: Connected to FRANKFURT in TUN mode, running on tun0

ip addr show tun0
# Должен показать IP в диапазоне 172.16.x.x
```

### Шаг 3: Изменить DNS на VPN DNS

**Вариант 1: Через настройки AdGuard VPN (рекомендуется)**
```bash
# Включить опцию "Change system DNS" в AdGuard VPN
adguardvpn-cli config set-change-system-dns on
```

**Вариант 2: Вручную через systemd-resolved**
```bash
# Создать конфиг для VPN
sudo tee /etc/systemd/resolved.conf.d/vpn.conf > /dev/null << 'EOF'
[Resolve]
DNS=127.0.0.1:46735
FallbackDNS=8.8.8.8
DNSSEC=no
Cache=no
EOF

# Перезапустить systemd-resolved
sudo systemctl restart systemd-resolved

# Проверить
resolvectl status
# Должно показать DNS через 127.0.0.1:46735 (AdGuard)
```

### Шаг 4: Проверить DNS через VPN
```bash
# Проверить что DNS работает через VPN
dig google.com +short
# Должен вернуть IP

# Проверить что IP через VPN
curl -s ifconfig.me
# Должен показать IP VPN (например, 156.146.33.99)
```

### Шаг 5: Проверить Kilo Code
- Перезапустите VS Code/Kilo Code
- Попробуйте подключиться к нейросетям
- Должно работать!

---

## Как вернуться к базовому DNS (без VPN)

Если нужно отключить VPN и вернуть базовый DNS:

```bash
# 1. Отключить VPN
adguardvpn-cli disconnect

# 2. Восстановить systemd-resolved
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
sudo rm -f /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 3. Удалить VPN конфиг
sudo rm -f /etc/systemd/resolved.conf.d/vpn.conf

# 4. Проверить
dig google.com +short
sudo apt update
```

---

## Полезные команды

### Проверить текущий DNS
```bash
cat /etc/resolv.conf
resolvectl status
```

### Проверить что слушает порт 53
```bash
ss -ltpn | grep 53
```

### Проверить маршрутизацию
```bash
ip rule show
ip route show table all
```

### Проверить VPN статус
```bash
adguardvpn-cli status
adguardvpn-cli config show
```

---

## Policy routing (SSH сохраняется при VPN)

Уже настроено на вашем сервере:
```bash
ip rule show
# 30754: from 176.123.161.187 lookup 100

ip route show table 100
# default via 176.123.160.1 dev enp3s0 table 100
```

Это означает: весь трафик **от** IP 176.123.161.187 идет через провайдера, минуя VPN. SSH сессии сохраняются.

---

## Docker контейнеры

Docker контейнеры автоматически используют хост-резолвер, поэтому:
- С базовым DNS → резолвят через провайдера
- С VPN DNS → резолвят через AdGuard (VPN)

Если нужно явно указать DNS для Docker:
```bash
# В /etc/docker/daemon.json
{
  "dns": ["127.0.0.1"]
}
```

---

## Troubleshooting

### Kilo Code не работает с VPN
**Причина:** DNS резолвит через провайдера, а не через VPN  
**Решение:** Включить "Change system DNS" в AdGuard VPN или настроить systemd-resolved на 127.0.0.1:46735

### Apt не работает с VPN
**Причина:** DNS не работает  
**Решение:** Проверить что systemd-resolved работает и DNS настроен правильно

### SSH отключается при VPN
**Причина:** Нет policy routing  
**Решение:** Добавить правила:
```bash
IP=$(ip addr show enp3s0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
sudo ip rule add from $IP table 100
sudo ip route add default via 176.123.160.1 dev enp3s0 table 100
```

---

## Итоговая последовательность

**Для работы с VPN:**
1. `adguardvpn-cli connect -l FRANKFURT`
2. `adguardvpn-cli config set-change-system-dns on`
3. Перезапустить VS Code/Kilo Code

**Для работы без VPN:**
1. `adguardvpn-cli disconnect`
2. Восстановить базовый DNS (см. выше)

---

**Дата создания:** 2025-12-29  
**Статус:** ✅ Рабочая конфигурация