# Порядок запуска и управления

## 1) Создаём сеть заранее (bootstrap)

Создайте `vpn-net` один раз вручную (или скриптом) — тогда любой compose, объявивший `external: true`, не упадёт.

```bash
docker network inspect vpn-net >/dev/null 2>&1 || \
  docker network create vpn-net
```

В `docker-compose.yml` всех app/services используйте:

```yaml
networks:
  vpn-net:
    external: true
```

Плюс: поместите этот `docker network create` в `Makefile`/скрипт деплоя, чтобы команда была идемпотентной.

---

## 2) Порядок запуска (рекомендация)

Лучше запускать в таком порядке:

1. `vpn` (поднимает proxy и tun0)
2. `dev` / `apps`

Если нужен ручной запуск отдельно — это нормально, но порядок гарантирует, что `vpn` уже доступен.

---

## 3) Обрабатывать отсутствие proxy в приложениях

Если приложение критично зависит от proxy, дайте ему поведение fallback:

* вариант A: **ждать proxy** (healthcheck/loop) — приложение блокируется до появления `vpn:1080`;
* вариант B: **fallback на прямой доступ** (если допустимо с точки зрения безопасности);
* вариант C: **запускать с restart-policy и healthcheck** — контейнер сам перезапустится, если не может подключиться.

---

## 4) Опция «stub proxy» (если надо, но с оговорками)

Можно держать лёгкий stub-proxy (small sidecar) всегда запущенным, который принимает connections на `vpn:1080` и:

* либо ответит ошибкой / 502, пока реальный proxy не появился,
* либо пробросит трафик напрямую в интернет (если вы хотите «мягкий» fallback).

Минусы: такой stub может по ошибке дать egress вне VPN → надо внимательно продумать поведение и безопасность.

---

## 5) dev с `network_mode: "container:vpn"`

Для dev: если вы используете `network_mode: "container:vpn"`, то dev будет работать **только** если контейнер с точным именем `vpn` запущен. Это хороший способ гарантировать, что dev всегда имеет те же маршруты/DNS, что vpn. Но обратный эффект: вы не сможете поднять dev если vpn остановлен.

---

## Как запустить — quickstart

1. Bootstrap (один раз):

```bash
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

2. Поднять vpn:

```bash
cd vpn
docker compose up -d
```

3. Поднять dev:

```bash
cd dev
docker compose up -d
```

4. Поднять apps:

```bash
cd apps
docker compose up -d
```

5. Проверки (из `dev` контейнера, т.к. он шарит netns с `vpn`):

```bash
# Выполнить в отдельном терминале после старта контейнеров
docker exec -it dev bash
# Проверить внешний IP через tinyproxy
curl --proxy http://127.0.0.1:1090 https://api.ipify.org
# Проверить через socks5 (например, с curl + proxychains или приложение, поддерживающее socks5h)
```
