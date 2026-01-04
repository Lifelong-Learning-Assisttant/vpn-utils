# Результаты тестирования DNS решений

## Дата тестирования
2026-01-03

## Тестовая среда
- **OS:** Linux 5.15
- **Podman:** версия неизвестна
- **VPN:** AdGuard VPN CLI
- **VPN namespace:** vpn-ns
- **VPN интерфейс:** tun0 с IP 172.16.219.2/32

---

## Результаты тестирования

### 1. Cloudflared (DoH proxy)

#### Команда запуска
```bash
sudo podman run -d --name cloudflared-test \
  --network=ns:/run/netns/vpn-ns \
  docker.io/cloudflare/cloudflared:latest \
  proxy-dns --address 0.0.0.0 --port 5353 \
    --upstream https://1.1.1.1/dns-query \
    --upstream https://1.0.0.1/dns-query
```

#### Результаты
- ✅ Контейнер успешно запустился на порту 5353
- ✅ cloudflared слушает на порту 5353
- ❌ DNS запросы через cloudflared не работают (SERVFAIL)

#### Логи cloudflared
```
2026-01-03T15:31:18Z INF Adding DNS upstream url=https://1.1.1.1/dns-query
2026-01-03T15:31:18Z INF Adding DNS upstream url=https://1.0.0.1/dns-query
2026-01-03T15:31:18Z INF Starting DNS over HTTPS proxy server address=dns://0.0.0.0:5353
2026-01-03T15:31:18Z INF Starting metrics server on 127.0.0.1:34393/metrics
2026-01-03T15:37:16Z ERR failed to connect to an HTTPS backend "https://1.1.1.1/dns-query" error="failed to perform an HTTPS request: Post \"https://1.1.1.1/dns-query\": dial tcp 1.1.1.1:443: connect: connection refused"
2026-01-03T15:37:16Z ERR failed to connect to an HTTPS backend "https://1.0.0.1/dns-query" error="failed to perform an HTTPS request: Post \"https://1.0.0.1/dns-query\": dial tcp 1.0.0.1:443: connect: connection refused"
```

#### Вывод
cloudflared не может подключиться к upstream серверам по HTTPS (порт 443), потому что VPN блокирует HTTPS соединения.

---

### 2. Unbound (TCP DNS resolver)

#### Попытка запуска
```bash
sudo podman run -d --name unbound-test \
  --network=ns:/run/netns/vpn-ns \
  -v /home/llm-dev/project/lifelong_learning_assistant/vpn-utils/unbound.conf:/etc/unbound/unbound.conf:ro \
  docker.io/alpine:latest \
  sh -c "apk add --no-cache unbound && unbound -d -c /etc/unbound/unbound.conf"
```

#### Результаты
- ❌ Контейнер не может установить unbound, потому что DNS не работает в VPN namespace

#### Логи
```
WARNING: fetching https://dl-cdn.alpinelinux.org/alpine/v3.23/main/x86_64/APKINDEX.tar.gz: DNS: transient error (try again later)
WARNING: fetching https://dl-cdn.alpinelinux.org/alpine/v3.23/community/x86_64/APKINDEX.tar.gz: DNS: transient error (try again later)
ERROR: unable to select packages:
  unbound (no such package):
    required by: world[unbound]
```

#### Вывод
Невозможно установить unbound в контейнере в VPN namespace, потому что DNS не работает.

---

### 3. Тестирование DNS в VPN namespace

#### Маршрутизация в VPN namespace
```bash
$ sudo ip netns exec vpn-ns ip route show
default dev tun0 scope link 
10.0.0.0/24 dev veth-ns proto kernel scope link src 10.0.0.2 
10.88.0.0/0/16 dev cni-podman0 proto kernel scope link src 10.88.0.1 linkdown 
```

#### Тестирование портов
```bash
# Порт 53 (TCP) - доступен
$ sudo ip netns exec vpn-ns nc -zv 8.8.8.8 53
Connection to 8.8.8.8 53 port [tcp/domain] succeeded!

# Порт 443 (HTTPS) - недоступен
$ sudo ip netns exec vpn-ns nc -zv 8.8.8.8 443
nc: connect to 8.8.8.8 port 443 (tcp) failed: Connection refused

# Порт 80 (HTTP) - недоступен
$ sudo ip netns exec vpn-ns nc -zv 1.1.1.1 80
nc: connect to 1.1.1.1 port 80 (tcp) failed: Connection refused
```

#### Тестирование DNS запросов
```bash
# UDP DNS запрос - таймаут
$ sudo ip netns exec vpn-ns dig @8.8.8.8 google.com
;; communications error to 8.8.8.8#53: timed out

# TCP DNS запрос - таймаут
$ sudo ip netns exec vpn-ns dig @8.8.8.8 +tcp google.com
;; communications error to 8.8.8.8#53: timed out

# AdGuard DNS запрос - таймаут
$ sudo ip netns exec vpn-ns dig @94.140.14.14 google.com
;; communications error to 94.140.14.14#53: timed out
```

#### Тестирование ping
```bash
$ sudo ip netns exec vpn-ns ping -c 2 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
--- 8.8.8.8 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss, time 1012ms
```

---

## Анализ проблем

### Основная проблема
VPN namespace не может разрешать DNS, хотя порт 53 доступен для TCP соединений.

### Возможные причины
1. **VPN блокирует DNS запросы** - AdGuard VPN CLI может блокировать DNS запросы, даже если порт 53 доступен
2. **Проблема с маршрутизацией** - хотя маршрут по умолчанию идет через tun0, DNS запросы не проходят
3. **VPN блокирует ICMP** - ping не работает в VPN namespace

### Что работает
- ✅ Порт 53 доступен для TCP соединений
- ✅ Маршрутизация настроена правильно (default dev tun0)
- ✅ VPN интерфейс tun0 доступен с IP 172.16.219.2/32

### Что не работает
- ❌ DNS запросы (UDP и TCP) таймаутят
- ❌ HTTPS соединения (порт 443) недоступны
- ❌ HTTP соединения (порт 80) недоступны
- ❌ ICMP (ping) не работает

---

## Выводы

### Cloudflared
❌ **Не работает** - требует HTTPS (порт 443), который блокируется VPN

### Unbound
❌ **Не протестировано** - невозможно установить в контейнере в VPN namespace из-за отсутствия DNS

### DNS в VPN namespace
❌ **Не работает** - DNS запросы таймаутят, хотя порт 53 доступен

---

## Рекомендации

### 1. Исследовать VPN конфигурацию
- Проверить настройки AdGuard VPN CLI
- Найти способ разрешить DNS запросы в VPN namespace
- Проверить, есть ли возможность настроить DNS серверы в AdGuard VPN CLI

### 2. Использовать DNS на хосте
- Запустить DNS сервер на хосте
- Настроить контейнер использовать DNS сервер на хосте
- Пробросить DNS запросы через VPN

### 3. Использовать другой VPN
- Попробовать другой VPN клиент, который поддерживает DNS в namespace
- Найти VPN, который не блокирует DNS запросы

### 4. Использовать VPN на уровне приложения
- Не использовать VPN namespace
- Настроить VPN на уровне приложения внутри контейнера
- Использовать прокси или SOCKS5

---

## Следующие шаги

1. Исследовать конфигурацию AdGuard VPN CLI
2. Найти способ разрешить DNS запросы в VPN namespace
3. Протестировать DNS решения после решения проблемы с DNS
4. Обновить документацию с рабочим решением
