# Базовые настройки DNS для Ubuntu 22.04

## Исходные настройки (чистый сервер)

### Сетевые интерфейсы
```bash
ip addr show
```
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN
    inet 127.0.0.1/8 scope host lo
2: enp3s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 disc fq_codel state UP
    inet 176.123.161.187/21 metric 100 brd 176.123.167.255 scope global dynamic enp3s0
```

### Маршрутизация
```bash
ip route show
```
```
default via 176.123.160.1 dev enp3s0 proto dhcp src 176.123.161.187 metric 100
176.123.160.0/21 dev enp3s0 proto kernel scope link src 176.123.161.187 metric 100
```

### DNS (systemd-resolved)
```bash
cat /etc/resolv.conf
```
```
# This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
nameserver 127.0.0.53
options edns0 trust-ad
search .
```

### Статус systemd-resolved
```bash
systemctl status systemd-resolved
```
```
● systemd-resolved.service - Network Name Resolution
     Loaded: loaded (/lib/systemd/system/systemd-resolved.service; enabled; vendor preset: enabled)
     Active: active (running)
```

### Прослушиваемые порты
```bash
ss -ltpn
```
```
LISTEN   0    4096    127.0.0.53%lo:53      0.0.0.0:*              
LISTEN   0    128        0.0.0.0:22          0.0.0.0:*              
```

### /etc/hosts
```bash
cat /etc/hosts
```
```
127.0.0.1 localhost
127.0.1.1 ubuntu2204

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
```

---

## Команды для восстановления базовых настроек

Если DNS сломался (например, после экспериментов с VPN/AdGuard), выполните:

### 1. Остановить все кастомные DNS-процессы
```bash
# Остановить все инструменты для forwarding портов.

# Остановить dnsmasq если установлен
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true
```

### 2. Включить и запустить systemd-resolved
```bash
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
```

### 3. Восстановить /etc/resolv.conf
```bash
# Удалить старый файл
sudo rm -f /etc/resolv.conf

# Создать ссылку на stub-resolver
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

### 4. Проверить результат
```bash
# Проверить файл
cat /etc/resolv.conf

# Проверить статус службы
systemctl status systemd-resolved

# Проверить порт 53
ss -ltpn | grep 53

# Проверить DNS
dig google.com +short
ping -c 2 google.com

# Проверить apt
sudo apt update
```

---

## Что делает systemd-resolved?

- **Слушает порт 53** на `127.0.0.53` (локальный DNS-резолвер)
- **Пересылает запросы** на upstream DNS (обычно от DHCP провайдера)
- **Кеширует** ответы для ускорения
- **Интегрирован** с системой (NetworkManager, systemd-networkd)

---

## Когда использовать этот подход?

✅ **Используйте systemd-resolved когда:**
- Нужен простой рабочий DNS
- Не требуется VPN для DNS
- Нужна базовая функциональность

❌ **Не используйте когда:**
- Нужен AdGuard/VPN для DNS
- Требуется selective forwarding
- Нужен кастомный DNS-сервер

---

## Полезные команды диагностики

```bash
# Проверить что слушает порт 53
ss -ltpn | grep 53
ss -ulpn | grep 53
sudo lsof -i :53

# Проверить DNS-запросы
dig @127.0.0.53 google.com
dig google.com
dig @8.8.8.8 google.com

# Проверить маршрутизацию
ip route show
ip rule show

# Проверить сетевые интерфейсы
ip addr show

# Проверить systemd-resolved
resolvectl status
resolvectl query google.com
```

---

## Важные файлы

- `/etc/resolv.conf` — ссылка на DNS-резолвер
- `/run/systemd/resolve/stub-resolv.conf` — управляемый systemd файл
- `/etc/hosts` — локальные хосты
- `/etc/systemd/system/systemd-resolved.service` — конфиг службы

---

## Восстановление после AdGuard VPN

Если после AdGuard VPN DNS сломался:

```bash
# 1. Отключить VPN
adguardvpn-cli disconnect

# 2. Завершить все DNS-процессы
# (если они есть)
sudo systemctl stop dnsmasq 2>/dev/null || true

# 3. Восстановить systemd-resolved
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
sudo rm -f /etc/resolv.conf
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 4. Проверить
dig google.com +short
sudo apt update
```

---

## Policy routing для SSH (сохранение доступа при VPN)

### Исходные настройки
```bash
ip rule show
```
```
0:      from all lookup local
30754:  from 176.123.161.187 lookup 100
32766:  from all lookup main
32767:  from all lookup default
```

```bash
ip route show table 100
```
```
default via 176.123.160.1 dev enp3s0 table 100
```

### Что делает policy routing:
- **Правило 30754**: Весь трафик **от** IP 176.123.161.187 идет через таблицу 100
- **Таблица 100**: Использует провайдерский шлюз (176.123.160.1), минуя VPN
- **Результат**: SSH сессии сохраняются даже при включенном VPN

### Как восстановить (если правила пропали):

```bash
# 1. Узнать свой IP адрес
IP_ADDR=$(ip addr show enp3s0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "Ваш IP: $IP_ADDR"

# 2. Добавить правило routing
sudo ip rule add from $IP_ADDR table 100

# 3. Добавить маршрут в таблицу 100
sudo ip route add default via 176.123.160.1 dev enp3s0 table 100

# 4. Проверить
ip rule show
ip route show table 100
```

### Сохранение правил после перезагрузки сервера:

Создайте файл `/etc/network/if-up.d/policy-routing`:

```bash
sudo tee /etc/network/if-up.d/policy-routing > /dev/null << 'EOF'
#!/bin/bash
# Policy routing for SSH to survive VPN

if [ "$IFACE" = "enp3s0" ] && [ "$MODE" = "start" ]; then
    IP=$(ip addr show enp3s0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$IP" ]; then
        ip rule add from $IP table 100 2>/dev/null || true
        ip route add default via 176.123.160.1 dev enp3s0 table 100 2>/dev/null || true
    fi
fi
EOF

sudo chmod +x /etc/network/if-up.d/policy-routing
```

### Проверка работы:

```bash
# Подключитесь по SSH
# В другом терминале на сервере запустите:
sudo ip route add default via 10.255.255.1 dev tun0 table 100 2>/dev/null || true
adguardvpn-cli connect

# SSH сессия должна остаться активной!
```

---

## Чек-лист после восстановления

- [ ] `cat /etc/resolv.conf` показывает `nameserver 127.0.0.53`
- [ ] `systemctl status systemd-resolved` — active (running)
- [ ] `ss -ltpn | grep 53` — слушает на 127.0.0.53:53
- [ ] `dig google.com +short` — возвращает IP
- [ ] `ping -c 2 google.com` — работает
- [ ] `sudo apt update` — работает без ошибок DNS
- [ ] SSH доступ сохраняется
- [ ] Policy routing настроен (ip rule show)

---

## Примечания

- **Cloud.ru** по умолчанию использует systemd-resolved
- **Не меняйте** `/etc/resolv.conf` вручную — он управляется systemd
- **Если нужно** статический DNS — используйте `/etc/systemd/resolved.conf`
- **Policy routing** для SSH настраивается отдельно (если нужен VPN)

---

**Дата создания:** 2025-12-29  
**Автор:** Инструкция для восстановления базовых настроек DNS  
**Статус:** ✅ Рабочий