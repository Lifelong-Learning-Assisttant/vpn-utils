# Практическая реализация

## Структура файлов

```
./vpn/
  Dockerfile
  entrypoint.sh
  danted.conf
  tinyproxy.conf
  dnsmasq.conf
  docker-compose.yml
./dev/
  Dockerfile
  docker-compose.yml
./apps/
  docker-compose.yml
./scripts/
  bootstrap.sh
```

---

## vpn/Dockerfile

```Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl iproute2 iputils-ping procps \
    dnsmasq tinyproxy dante-server sudo \
 && rm -rf /var/lib/apt/lists/*

# Конфиги и скрипт
COPY danted.conf /etc/danted.conf
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 1080 1090

# Не пробрасываем порты наружу на хост — они нужны для связи внутри docker-сети
CMD ["/usr/local/bin/entrypoint.sh"]
```

---

## vpn/danted.conf (шаблон)

```text
# Dante SOCKS server config (dante-server)
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = 1080
external: tun0
method: none
user.privileged: root
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
}
```

> Примечание: `external: tun0` гарантирует, что выходящий трафик dante будет идти через VPN-интерфейс. Если tun0 ещё не поднят на момент старта, entrypoint.sh ждёт интерфейс.

---

## vpn/tinyproxy.conf (шаблон)

```text
User nobody
Group nogroup
Port 1090
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
Logfile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Notice
PidFile "/var/run/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10

# allow local docker networks (по умолчанию разрешаем все внутренние запросы)
Allow 127.0.0.1
Allow 0.0.0.0/0

# Прослушивать на всех интерфейсах внутри контейнера — dev (network_mode: container:vpn) и другие контейнеры подключённые к vpn-net смогут обращаться по имени 'vpn:1090'
Listen 0.0.0.0

# Разрешаем CONNECT (HTTPS)
ConnectPort 443
ConnectPort 563
ConnectPort 80
```

---

## vpn/dnsmasq.conf (шаблон — используем публичные AdGuard DNS сервера)

```text
# dnsmasq простая конфигурация для локального резолвера
no-resolv
server=94.140.14.14
server=94.140.15.15
listen-address=127.0.0.1
bind-interfaces
cache-size=1000
```

> Если у вас есть свой AdGuard DNS/AdGuard VPN клиент — можно изменить server= на локальный адрес.

---

## vpn/entrypoint.sh

```bash
#!/bin/bash
set -e

# Лог в stdout
mkdir -p /var/log

# 1) Опционально: запустить VPN-клиент (adguardvpn-cli или любой другой)
# Если вы используете adguardvpn-cli и передаёте токен через ADGUARDVPN_TOKEN, попытка соединения будет предпринята.
# Пример: docker compose run -e ADGUARDVPN_TOKEN=... vpn

if [ -n "${ADGUARDVPN_TOKEN:-}" ]; then
  echo "[entrypoint] ADGUARDVPN_TOKEN задан — пытаемся запустить adguardvpn-cli"
  if command -v adguardvpn-cli >/dev/null 2>&1; then
    adguardvpn-cli login --token "$ADGUARDVPN_TOKEN" || true
    adguardvpn-cli connect --tcp || true
  else
    echo "[entrypoint] adguardvpn-cli не установлен в контейнере. Пропускаем запуск VPN-клиента."
  fi
fi

# 2) Запускаем dnsmasq (локальный резолвер) — обеспечивает резолв внутри vpn-namespace
if [ -f /etc/dnsmasq.conf ]; then
  echo "[entrypoint] старт dnsmasq"
  pkill dnsmasq || true
  dnsmasq --conf-file=/etc/dnsmasq.conf || true
fi

# 3) Ждём появления tun0 (если ожидается VPN-интерфейс)
# Ждём максимум 30s — если нет tun0, продолжим, но danted external может быть некорректен
for i in {1..30}; do
  if ip link show tun0 >/dev/null 2>&1; then
    echo "[entrypoint] интерфейс tun0 найден"
    break
  fi
  echo "[entrypoint] ждём tun0... ($i/30)"
  sleep 1
done

# 4) Запускаем danted (socks5)
if [ -f /etc/danted.conf ]; then
  echo "[entrypoint] старт danted"
  pkill danted || true
  /usr/sbin/danted -f /etc/danted.conf &
fi

# 5) Запускаем tinyproxy (http)
if [ -f /etc/tinyproxy/tinyproxy.conf ]; then
  echo "[entrypoint] старт tinyproxy"
  pkill tinyproxy || true
  tinyproxy -c /etc/tinyproxy/tinyproxy.conf &
fi

# 6) Вывод логов в foreground (простейший способ держать контейнер живым)
# Выводим основные логи в stdout для удобства
sleep 1

# tail логов по всем возможным файлам
mkdir -p /var/log/tinyproxy /var/log
# Не все файлы могут существовать сразу — используем tail -F
tail -F /var/log/danted.log /var/log/tinyproxy/tinyproxy.log || true

# Если tail завершится — контейнер тоже завершится
```

---

## vpn/docker-compose.yml

```yaml
version: "3.8"

services:
  vpn:
    container_name: vpn
    build: .
    cap_add:
      - NET_ADMIN
    cap_drop:
      - ALL
    devices:
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped
    networks:
      - vpn-net
    volumes:
      - ./danted.conf:/etc/danted.conf:ro
      - ./tinyproxy.conf:/etc/tinyproxy/tinyproxy.conf:ro
      - ./dnsmasq.conf:/etc/dnsmasq.conf:ro

networks:
  vpn-net:
    external: true
```

🔑 **Важно**

* compose **НЕ создаёт сеть**
* он ожидает, что `vpn-net` уже существует
* vpn может быть перезапущен независимо

---

## dev/Dockerfile

```Dockerfile
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git build-essential sudo iproute2 procps \
 && rm -rf /var/lib/apt/lists/*

# Папка рабочего проекта (примеры)
ARG USER=developer
ARG UID=1000
RUN useradd -m -u ${UID} -s /bin/bash ${USER} && echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER}
USER ${USER}
WORKDIR /home/${USER}/project

# --- Рекомендации по установке code-server и Kilo CLI ---
# Мы не ставим code-server и kilo в образ автоматически — разные проекты требуют разной версии и token'ов.
# Ниже — команды, которые можно выполнить внутри контейнера (или добавить в Dockerfile при желании):
#
# 1) Установить code-server (пример):
#   curl -fsSL https://code-server.dev/install.sh | sh
#
# 2) Установить Kilo CLI (пример):
#   curl -fsSL https://get.kilo.sh | sh
#
# 3) Настроить HTTP_PROXY/HTTPS_PROXY (если нужно), см. docker-compose — dev будет share net namespace с vpn.

CMD ["/bin/bash"]
```

---

## dev/docker-compose.yml

```yaml
version: "3.8"

services:
  dev:
    container_name: dev
    build: .
    network_mode: "container:vpn"
    restart: unless-stopped
    volumes:
      - dev-data:/home/developer
      - ./project:/home/developer/project
    environment:
      - HTTP_PROXY=http://127.0.0.1:1090
      - HTTPS_PROXY=http://127.0.0.1:1090
      - NO_PROXY=localhost,127.0.0.1

volumes:
  dev-data:
```

**Что это даёт**

* dev **НЕ зависит от compose vpn**
* но **зависит от факта существования контейнера `vpn`**
* `docker compose up dev` упадёт, если `vpn` не запущен — и это **правильное поведение**

---

## apps/docker-compose.yml

```yaml
version: "3.8"

services:
  app1:
    image: ubuntu:22.04
    command: sleep infinity
    networks:
      - vpn-net
    environment:
      - ALL_PROXY=socks5h://vpn:1080

networks:
  vpn-net:
    external: true
```

---

## scripts/bootstrap.sh

```bash
#!/usr/bin/env bash
set -e

docker network inspect vpn-net >/dev/null 2>&1 || \
  docker network create vpn-net
```

✔ просто
✔ прозрачно
✔ безопасно
✔ production-friendly
