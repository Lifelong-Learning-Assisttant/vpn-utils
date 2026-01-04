# Помощь от GPT5

Отличное и детальное описание — спасибо, всё понятно. Ниже — практически применимое руководство + несколько вариантов (с командами), чтобы приложения в вашем контейнере снова получали рабочий DNS через AdGuard VPN CLI, который, как вы заметили, фактически пропускает/поддерживает только TCP/DoH/DoT-пути для upstream DNS.

# Ключевая идея (коротко)

Лучше всего — запустить локальный DNS-«стаб» в том же network namespace `vpn-ns`, который будет принимать обычные **UDP**-запросы от приложений и пересылать их уже по **TCP/DoH/DoT** через VPN. То есть: приложение → локальный прокси (UDP) → прокси делает DoH/DoT/TCP → upstream (через AdGuard VPN CLI). Это решает проблему без правок приложений и без изменения AdGuard (который, судя по документации/реалиям, не поддерживает «прозрачный» UDP→TCP проксинг сам по себе). ([GitHub][1])

Ниже — варианты, конкретные утилиты и пошаговые примеры для Podman.

---

# Вариант A — **Рекомендуемый** (проще всего): запустить **cloudflared** (DoH proxy) в том же netns

**Почему:** `cloudflared` умеет слушать локально (UDP+TCP на 127.0.0.1:53) и пересылать запросы через DoH (HTTPS). Это корректно реализует протоколы и «фрейминг» TCP для DNS, в отличие от простых UDP→TCP реле. ([DEV Community][2])

Пример команд (sidecar-подход — отдельный контейнер, но в том же net namespace `vpn-ns`):

1. Запустить cloudflared в VPN netns (в этом примере использую официальный образ `cloudflare/cloudflared` — проверяйте тэги у себя):

```bash
sudo podman run -d --name cloudflared \
  --network=ns:/run/netns/vpn-ns \
  docker.io/cloudflare/cloudflared:latest \
  proxy-dns --address 127.0.0.1 --port 53 \
            --upstream https://1.1.1.1/dns-query \
            --upstream https://1.0.0.1/dns-query
```

Этот контейнер будет слушать 127.0.0.1:53 внутри `vpn-ns` и форвардить DNS через DoH (HTTPS) — то есть запросы пройдут по TCP/HTTPS через VPN. ([DEV Community][2])

2. Запустить ваш рабочий контейнер в том же netns и указать DNS на `127.0.0.1`:

```bash
sudo podman run -it --rm \
  --network=ns:/run/netns/vpn-ns \
  --dns 127.0.0.1 \
  docker.io/alpine:latest sh
```

Внутри контейнера `127.0.0.1` — это loopback в общем net namespace (cloudflared и ваш контейнер разделяют netns), поэтому резолвинг будет идти к running `cloudflared`. Теперь `nslookup`/`dig` через UDP к 127.0.0.1 должны работать.

3. Тест:

```bash
# в контейнере
apk add --no-cache bind-tools
dig @127.0.0.1 example.com
```

Плюсы:

* Простая реализация, проверенная в многих сценариях (Pi-hole, домашние маршрутизаторы и пр.). ([Pi-hole Userspace][3])
  Минусы/заметки:
* Нужен дополнительный контейнер/процесс (но это нормально — sidecar pattern).
* cloudflared использует DoH (HTTPS) — это точно проходит через TCP/HTTPS, который ваш VPN обрабатывает.

---

# Вариант B — Запустить **dnscrypt-proxy** / **stubby** / **unbound (forward-to-DoT)** локально

**Коротко:** несколько альтернатив, реализующих локальный stub resolver и умеющих форвардить к upstream по защищённым каналам (DoH / DoT / DNSCrypt). Они корректно принимают UDP от приложений и пересылают через TCP/HTTPS/TLS.

* **dnscrypt-proxy** — поддерживает DoH/DoT/DNSCrypt, часто используется вместе с Pi-hole. Пример: слушать на `127.0.0.1:5053` и иметь upstream DoH. ([GitHub][4])
* **Stubby** — минималистичный локальный stub resolver для DoT (getdns/stubby). ([GitHub][5])
* **Unbound** — можно настроить как локальный forwarder и включить `forward-tls-upstream: yes` и `forward-addr: 1.1.1.1@853` (то есть Unbound будет пересылать по DoT/TLS). Это даёт полноценный локальный резолвер. ([Super User][6])

Как запустить: тот же pattern — sidecar-контейнер с `--network=ns:/run/netns/vpn-ns`, слушающий на 127.0.0.1:53 (или 127.0.0.1:5053 и указать `--dns 127.0.0.1#5053`/монтировать resolv.conf).

Плюсы:

* Более гибкая настройка (DoT, кеш, DNSSEC и пр.).
  Минусы:
* Нужна конфигурация (особенно для unbound/dnscrypt-proxy), чуть больше работы, чем cloudflared.

---

# Вариант C — «Хак»: попытаться на хосте перехватывать UDP и переводить в TCP

Я *не рекомендую* делать «простую» переадресацию UDP→TCP (через `socat`/`iptables`), потому что DNS-over-TCP требует спецификации (framing, length-prefix) — простая пересылка UDP payload на TCP-сокет часто ломается. Лучше использовать полноценный DNS-прокси (cloudflared / dnscrypt-proxy / unbound) который правильно реализует протокол. (Технически есть отдельные утилиты-«туннели», но они ненадёжны для DNS; используйте специализированные resolver-прокси). ([DEV Community][2])

---

# Вариант D — менять настройки AdGuard VPN CLI

Можно посмотреть, поддерживает ли ваша версия AdGuard VPN CLI «DNS over UDP passthrough» или менять режим проксирования (например, SOCKS5 с UDP ASSOCIATE — но не все приложения используют SOCKS5 UDP). Документация AdGuard VPN CLI/KB стоит проверить — в некоторых режимах AdGuard может проксировать UDP через SOCKS5, но это не универсально и зависит от версии/настроек. Поэтому это менее универсально, чем локальный stub. ([AdGuard VPN][7])

---

# Практические детали для Podman и ваш случай

1. **Где ставить прокси — в хосте или в контейнере?**

   * **Лучше — внутри того же network namespace**, то есть запустить proxy-контейнер с `--network=ns:/run/netns/vpn-ns`. Тогда все DNS запросы пойдут через VPN. Устанавливать на хосте не обязательно.
   * Можно также установить proxy внутри самого приложения-контейнера (если вы контролируете образ), но sidecar даёт гибкость (можно обновлять прокси отдельно).

2. **Как прописать DNS для контейнера?**

   * `--dns 127.0.0.1` при запуске контейнера (и при условии, что в этом netns есть слушатель на 127.0.0.1:53). Podman перепишет `/etc/resolv.conf`. Альтернативно — примонтировать заранее подготовленный `/etc/resolv.conf`.

3. **Пара тестов для отладки:**

```bash
# Проверить TCP к upstream (у вас уже работает)
nc -zv 8.8.8.8 53

# В контейнере (после запуска cloudflared) проверить локальный резолвер:
dig @127.0.0.1 example.com

# Если хотите убедиться, что UDP к 8.8.8.8 раньше таймаутил:
dig @8.8.8.8 example.com +time=2 +tries=1   # ожидался таймаут по UDP
# Затем через локальный proxy должно работать:
dig @127.0.0.1 example.com
```

---

# Короткие ответы на ваши вопросы по порядку

* **Существует ли утилита для «переупаковать» UDP→TCP для DNS?**
  Да — это полноценные локальные DNS-прокси/стабы (cloudflared, dnscrypt-proxy, stubby, unbound в forward-to-DoT режиме). Они принимают UDP/TCP локально и форвардят upstream по DoH/DoT/TCP корректно. ([DEV Community][2])

* **Как она называется?**

  * `cloudflared` (DoH proxy / proxy-dns) — самый быстрый путь. ([DEV Community][2])
  * `dnscrypt-proxy` — гибкий, поддерживает DoH/DoT/DNSCrypt. ([GitHub][4])
  * `stubby` — локальный DoT stub. ([GitHub][5])
  * `unbound` — локальный forwarder с `forward-tls-upstream: yes`. ([Super User][6])

* **Как её настроить в контейнере? Нужно ли на хосте?**
  Запускать в контейнере (sidecar) в том же netns — самый простой и рекомендуемый путь. Не нужно ставить на хосте. Подробный пример с `cloudflared` выше.

* **Можно ли настроить приложения на DoT/DoH? Поддерживает ли Podman `--dns` для DoH/DoT? Как настроить code-server?**

  * Большинство приложений используют системный резолвер и не умеют сами DoH/DoT. Некоторые приложения (браузеры) умеют DoH встроенно. `code-server` как правило использует системный DNS — проще дать ему локальный прокси.
  * `--dns` в Podman принимает IP-адрес(а) (обычный `resolv.conf`) — это не «DoH/DoT» настройка, а просто адрес резолвера. То есть Podman не умеет «передать DoH/DoT» — вы указываете IP локального прокси.
  * Для `code-server`: поставьте локальный proxy (cloudflared/dnscrypt-proxy) и запустите code-server с `--dns 127.0.0.1` или примонтируйте `/etc/resolv.conf` с `nameserver 127.0.0.1`.

* **Можно ли запустить локальный DNS прокси в контейнере, который будет конвертировать UDP→TCP? Какие есть?**
  Да — cloudflared / dnscrypt-proxy / stubby / unbound (см. выше). Интеграция через запуск в том же netns и указание `--dns` на 127.0.0.1.

* **Можно ли настроить AdGuard VPN CLI на поддержку UDP DNS?**
  Вероятно нет (или ограниченно) — документация и багрепорты показывают, что AdGuard VPN CLI/режимы ориентированы на TCP/HTTP(S) DNS (DoH/DoT) и SOCKS/TCP; прямой прозрачный UDP→TCP проксинг не всегда возможен. Лучше сделать локальный proxy. Проверьте релиз-ноты/настройки AdGuard CLI конкретной версии, но общий практический путь — использовать локальный stub. ([AdGuard VPN][7])

---

# Резюме и рекомендованный шаг (практика)

1. Запустите `cloudflared` как контейнер в `vpn-ns`, слушающий 127.0.0.1:53 и форвардящий на DoH (команда выше). ([DEV Community][2])
2. Запустите рабочие контейнеры в том же netns и укажите `--dns 127.0.0.1`.
3. Протестируйте `dig @127.0.0.1 example.com` — должно заработать.
4. При желании замените cloudflared на dnscrypt-proxy / stubby / unbound (если хотите DoT или кеш/разные функции).

Если хотите, могу:

* подготовить **готовые podman-команды**/compose-like манифест для запуска `cloudflared` + вашего контейнера;
* или предложить конфиг `dnscrypt-proxy`/`unbound` для DoT/DoH;
* или помочь проверить конфигурацию AdGuard VPN CLI (подскажите версию CLI) — могу поискать в их репозитории/релиз-нотах. ([GitHub][1])

Готов приступить к конкретной автоматизации (скрипты/манифесты) — скажите, какой вариант предпочитаете (cloudflared — быстрое решение; unbound/dnscrypt-proxy — более «серверное», с нюансами настройки).

[1]: https://github.com/AdguardTeam/AdGuardVPNCLI?utm_source=chatgpt.com "AdguardTeam/AdGuardVPNCLI: AdGuard VPN command-line version"
[2]: https://dev.to/mfat/how-to-proxy-dns-requests-using-cloudflared-58p7?utm_source=chatgpt.com "How to encrypt DNS requests using cloudflared - DEV Community"
[3]: https://discourse.pi-hole.net/t/dns-over-https-with-cloudflared-and-ipv6/48478?utm_source=chatgpt.com "DNS over HTTPS with cloudflared and IPv6! - Pi-hole Userspace"
[4]: https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml?utm_source=chatgpt.com "example-dnscrypt-proxy.toml - GitHub"
[5]: https://github.com/getdnsapi/stubby?utm_source=chatgpt.com "getdnsapi/stubby - GitHub"
[6]: https://superuser.com/questions/1311337/how-to-configure-unbound-to-validate-a-dns-over-tls-servers-certificate?utm_source=chatgpt.com "How to configure Unbound to validate a DNS over TLS server's ..."
[7]: https://adguard-vpn.com/kb/adguard-vpn-for-linux/settings/?utm_source=chatgpt.com "Settings | AdGuard VPN Knowledge Base"


# Помощь от Grok.

### 1. Утилита для преобразования UDP DNS в TCP DNS

Да, такие утилиты существуют для Linux. Они позволяют принимать стандартные UDP-запросы локально (внутри контейнера или на хосте) и преобразовывать их в TCP-запросы, которые проходят через VPN. Это решает проблему, поскольку VPN пропускает TCP-соединения на порт 53 (как указано в ваших тестах с `nc -zv 8.8.8.8 53`).

#### Рекомендуемые утилиты
- **utdns**: Специализированный инструмент для проксирования UDP DNS в TCP DNS. Это простой прокси, который перехватывает UDP-запросы и отправляет их по TCP, правильно обрабатывая протокол (включая префикс длины для TCP DNS).
  - **Установка**: Скачайте с GitHub и скомпилируйте (написан на C). В контейнере на базе Alpine: `apk add gcc make`, затем `git clone https://github.com/rahra/utdns`, `make`, `./utdns`.
  - **Настройка в контейнере**: Запустите как `utdns -l 127.0.0.1:53 -r 8.8.8.8:53` (слушает UDP на локальном 53, форвардит по TCP на 8.8.8.8:53). Укажите в `/etc/resolv.conf` контейнера `nameserver 127.0.0.1`. Добавьте в команду запуска контейнера `--dns=127.0.0.1` (перезапишет resolv.conf).
  - **Где устанавливать**: В контейнере — это изолировано и не влияет на хост. Если нужно для нескольких контейнеров, можно на хосте, но тогда настройте маршрутизацию портов в namespace.

- **Unbound** (рекурсивный DNS-резолвер): Может принимать UDP/TCP от приложений и форвардить upstream по TCP. Это более полный resolver с кэшированием.
  - **Установка**: В Alpine: `apk add unbound`.
  - **Настройка**: В файле `/etc/unbound/unbound.conf` добавьте:
    ```
    server:
        interface: 127.0.0.1
        do-udp: yes
        do-tcp: yes
        tcp-upstream: yes  # Форвард по TCP
    forward-zone:
        name: "."
        forward-addr: 8.8.8.8
    ```
    Запустите `unbound -d`. Настройте resolv.conf на `nameserver 127.0.0.1`.
  - **Где устанавливать**: В контейнере для простоты. Unbound лёгкий и подходит для Podman.

- **Socat или Netcat (nc) с скриптом**: Для простого прокси, но требует обработки префикса длины (DNS over TCP добавляет 2 байта длины перед запросом). Socat: `socat UDP-LISTEN:53,fork EXEC:'script.sh'` где script.sh добавляет/удаляет префикс. Это DIY-решение, менее надёжное, чем utdns или Unbound.
  - **Установка**: `apk add socat` или `apk add netcat-openbsd`.
  - **Настройка**: Скрипт на Bash/Python для преобразования. Запустите в фоне в контейнере.
  - **Где устанавливать**: В контейнере.

Рекомендую начать с Unbound — он стабилен, поддерживает кэш и легко настраивается. Если VPN блокирует только UDP на внешние серверы, локальный UDP внутри контейнера (на 127.0.0.1) будет работать нормально.

### 2. Альтернативные решения

#### Вариант 1: Использование DNS-over-TLS (DoT) или DNS-over-HTTPS (DoH)
- **Настройка приложений в контейнере**: Многие приложения (включая code-server) используют системный resolver (`/etc/resolv.conf`), который по умолчанию работает с plain DNS (UDP/TCP). Чтобы переключить на DoT/DoH, нужен stub-резолвер, поддерживающий эти протоколы, например systemd-resolved или stubby. В Alpine (ваш базовый образ) systemd нет, так что используйте stubby (для DoT) или doh-client (для DoH).
  - Установите stubby: `apk add stubby`. Настройте в `/etc/stubby/stubby.yml` upstream как `tls://8.8.8.8@853` (DoT на Google DNS). Запустите stubby, настройте resolv.conf на `nameserver 127.0.0.1`.
  - Для DoH: Используйте cloudflared (от Cloudflare) — `apk add cloudflared`, запустите как прокси DoH на локальном порту, затем настройте resolv.conf.
- **Поддержка в Podman**: Опция `--dns` принимает только IP-адреса (или списки), не схемы вроде `tls://` или `https://`. Для DoT/DoH настройте внутри контейнера, как выше. Podman позволяет сетевые плагины, но для DNS это не напрямую применимо.
- **Настройка code-server**: Code-server (на базе Node.js) использует системный DNS, так что настройка stub-резолвера (как stubby) сделает DoT/DoH прозрачным для него. Если code-server в отдельном контейнере, добавьте stubby туда. Для кастомной настройки: Node.js может использовать `dns.setServers()` в коде, но для готового code-server лучше системный подход.

Поскольку ваши тесты показывают, что DoH работает (`wget https://dns.google/resolve?...`), это хороший вариант — DoT/DoH построены на TCP/HTTPS, которые проходят через VPN.

#### Вариант 2: Использование локального DNS прокси
- **Возможность**: Да, запустите прокси в контейнере, который принимает UDP и конвертирует в TCP (как в разделе 1) или DoT/DoH.
- **Существующие DNS прокси для Linux**:
  - **dns-proxy-server** (для контейнеров): Поддерживает разрешение хостов из Docker/Podman, локальной БД и remote DNS. Установите в контейнере: Скачайте бинарник, запустите как `./dns-proxy-server --port=53 --default-resolver=8.8.8.8`. Интегрируйте с Podman, добавив в сеть и указав `--dns=ip_прокси`.
  - **Dnsmasq**: Лёгкий, принимает UDP/TCP, но upstream по умолчанию UDP. Для TCP используйте с unbound или в комбинации.
  - **GOST DNS Proxy**: Поддерживает множественные протоколы (UDP to TCP/DoT/DoH). Установите: `apk add go`, скомпилируйте из repo. Настройте как `gost -L dns://:53 -F dns://8.8.8.8:53/tcp`.
- **Интеграция с Podman**: Запустите прокси как отдельный контейнер в той же сети (`--network=ns:/run/netns/vpn-ns`), поделите namespace. Или в том же контейнере как sidecar-процесс (в entrypoint запустите прокси + sleep infinity). Укажите `--dns=127.0.0.1` или IP прокси.

#### Вариант 3: Изменение конфигурации AdGuard VPN CLI
- **Поддержка UDP DNS**: Нет, AdGuard VPN CLI не поддерживает UDP для DNS напрямую — оно фокусируется на TCP и SOCKS5-прокси (где UDP частично поддерживается, но не для всех apps). VPN CLI использует IPsec/IKEv2, который не нативно туннелирует UDP DNS без дополнительных настроек. В документации нет опций для включения UDP DNS.
- **Другие параметры**: Проверьте `--dns-upstream` или аналогичные в CLI (если доступны), но по поиску, стандартная конфиг (как "Change system DNS: on") не меняет поведение для UDP. Альтернатива: Используйте SOCKS5-режим AdGuard (`--socks5`), но приложения должны поддерживать SOCKS для DNS, что редко. Если возможно, настройте VPN на хосте без изменения system DNS, и используйте локальный resolver.

### Дополнительные идеи
- **Тестирование**: В вашем примере добавьте unbound или utdns в образ (создайте кастомный Dockerfile на базе alpine), запустите как sidecar. Проверьте `nslookup` внутри.
- **Безопасность**: DoT/DoH предпочтительнее plain TCP DNS для шифрования.
- **Если ничего не помогает**: Рассмотрите смену VPN на WireGuard (поддерживает UDP), но если AdGuard обязателен, stick to прокси.

Это должно решить DNS в контейнере через VPN. Если нужны точные команды или скрипты, уточните!

# Gemini pro

Это классическая проблема при работе с прокси или VPN-клиентами, которые ориентированы на TCP-трафик или имеют ограничения в реализации драйверов перехвата (TUN/TAP) в пространствах имен.

Поскольку у вас **TCP и HTTPS работают**, ваша задача — поставить «переводчика» (DNS Proxy), который примет UDP-запрос от приложения и отправит его дальше по TCP.

---

## 1. Рекомендуемые утилиты для преобразования UDP в TCP

Самый надежный способ — запустить локальный DNS-резолвер внутри того же namespace.

### Вариант А: Unbound (Профессиональное решение)

**Unbound** — это легковесный, но мощный рекурсивный DNS-сервер. Он умеет принудительно отправлять запросы вышестоящему серверу (upstream) только по TCP.

* **Как это работает:** Приложение обращается к `127.0.0.1:53` (UDP) -> Unbound принимает запрос -> Отправляет запрос к `8.8.8.8:53` (TCP) через VPN интерфейс.
* **Настройка в контейнере (Alpine):**
1. Установите: `apk add unbound`
2. Конфигурация (`/etc/unbound/unbound.conf`):
```yaml
server:
  interface: 127.0.0.1
  access-control: 127.0.0.0/8 allow
  do-udp: yes
  do-tcp: yes
  tcp-upstream: yes  # Ключевой параметр!

forward-zone:
  name: "."
  forward-addr: 8.8.8.8@53  # Google DNS

```

### Вариант Б: Socat (Быстрый "костыль" для теста)

Если вам нужно решение «здесь и сейчас» без сложных конфигов, можно использовать `socat`. Он просто перенаправит поток данных.

* **Команда внутри контейнера:**
```bash
socat UDP4-LISTEN:53,fork,reuseaddr TCP4:8.8.8.8:53

```


*Это создаст прослушивание на UDP 53 порту и будет транслировать всё в TCP на 8.8.8.8.*

---

## 2. Схема работы решения

Для наглядности, вот как будет проходить путь вашего DNS-запроса при использовании прокси-утилиты:

---

## 3. Ответы на ваши вопросы

### Где устанавливать утилиту?

Лучше всего устанавливать и запускать её **внутри контейнера** или как **sidecar-контейнер** в том же network namespace.

* Если вы используете один основной контейнер (как `test-vpn`), проще всего запустить прокси-процесс внутри него (например, через `supervisord` или простым скриптом запуска).

### Альтернативные решения (DoT/DoH)

1. **Настройка приложений на DoT/DoH:** Большинство стандартных утилит (curl, wget, ping) не умеют в DoH "из коробки" — они полагаются на системный резолвер. Поэтому настройка на уровне системы (через прокси) эффективнее.
2. **Podman `--dns`:** Параметр `--dns` просто прописывает IP в `/etc/resolv.conf`. Он **не умеет** превращать UDP в DoH/DoT самостоятельно.
3. **Code-server:** Он работает на Node.js. Node.js использует системный DNS. Если вы настроите локальный прокси и укажете `nameserver 127.0.0.1` в `/etc/resolv.conf`, code-server начнет работать автоматически.

### Можно ли настроить AdGuard VPN CLI?

Обычно AdGuard VPN CLI в Linux использует `tun` интерфейс и должен прозрачно обрабатывать UDP. Если это не работает, возможно:

* Включен режим **"DNS-over-HTTPS"** в самом AdGuard CLI, который перехватывает порт 53, но не слушает UDP внутри namespace.
* Попробуйте проверить команду `adguardvpn-cli config set-dns`. Если там стоит адрес DoH, попробуйте сбросить на системный или `8.8.8.8`.

---

## 4. Пошаговый план исправления (Best Practice)

Я рекомендую использовать **dnscrypt-proxy**, так как он наиболее гибок для задач VPN.

1. **Создайте Dockerfile** на базе вашего образа:
```dockerfile
FROM alpine:latest
RUN apk add --no-cache dnscrypt-proxy
# Настраиваем dnscrypt-proxy на принудительный TCP (force_tcp = true)
# И указываем слушать на 127.0.0.1:53
COPY dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
CMD ["sh", "-c", "dnscrypt-proxy & sleep infinity"]

```


2. **В конфигурации `dnscrypt-proxy.toml` укажите:**
```toml
force_tcp = true
listen_addresses = ['127.0.0.1:53']
upstream_servers = ['8.8.8.8:53'] # Или DoH сервер

```


3. **Запустите контейнер** с параметром `--dns=127.0.0.1`.

### Итог

Так как AdGuard VPN CLI в вашем случае уже обеспечил работающий TCP-канал, установка **маленького DNS-ретранслятора (UDP -> TCP)** внутри контейнера полностью решит проблему.

**Хотите, я помогу составить точный конфиг для `unbound` или `dnscrypt-proxy`, чтобы вы могли просто скопировать его в свой проект?**

# Perplexity

dns2tcp provides a lightweight solution to convert UDP DNS queries to TCP in your Podman container, addressing the AdGuard VPN CLI limitation. Install and run it inside the container on a custom port, then point the container's DNS to localhost for transparent proxying. This keeps everything within the VPN namespace without host modifications.[1]

## UDP-to-TCP Converter

dns2tcp listens on UDP (e.g., port 5353), forwards queries as TCP to 8.8.8.8:53 (which supports TCP), and returns responses. Compile from source or use prebuilt binaries from releases for Alpine: `apk add build-base git make`, then `git clone https://github.com/zfl9/dns2tcp && cd dns2tcp && make && cp dns2tcp /usr/local/bin/`.[1]

Run it as: `dns2tcp -L 127.0.0.1#5353 -R 8.8.8.8#53` in the background. Update container resolv.conf or launch command with `--dns 127.0.0.1:5353` (Podman supports port in --dns).[2][1]

For transparent redirection without changing --dns, use iptables inside the container: `iptables -t nat -A OUTPUT -p udp -d 8.8.8.8 --dport 53 -j REDIRECT --to-ports 5353` after starting dns2tcp.[1]

## Podman Integration

Modify your run command to `--dns 127.0.0.1#5353` and add an init script or entrypoint to start dns2tcp before your app: `podman run ... alpine:latest sh -c 'dns2tcp -L 127.0.0.1#5353 -R 8.8.8.8#53 & sleep infinity'`. This works in the vpn-ns since tun0 handles outbound TCP.[2]

Test with `nslookup ifconfig.me 127.0.0.1` inside the container—expect resolution via TCP tunnel.[1]

## Alternatives

**DNS Proxy (dnsmasq):** Alpine supports dnsmasq (`apk add dnsmasq`), configure `--server=8.8.8.8#53 --no-resolv` for TCP-only upstream on localhost:53/UDP. Simpler if needing caching.[3]

**DoH/DoT:** Podman --dns accepts IPs only, not DoT/DoH URIs; configure per-app (e.g., code-server via env vars like `RESOLVER_URL=https://dns.google/dns-query`). AdGuard CLI lacks UDP DNS enablement.[4][5][2]

**AdGuard Config:** No UDP DNS toggle; set-dns and change-system-dns=on already routes TCP DNS via tunnel. SOCKS mode unsupported for namespace sharing.[4]

[1](https://github.com/zfl9/dns2tcp)
[2](https://docs.podman.io/en/v5.0.1/markdown/podman-run.1.html)
[3](https://www.reddit.com/r/linuxadmin/comments/j3rgqm/configure_dnsmasq_to_only_use_specified_dns/)
[4](https://www.kali.org/tools/dns2tcp/)
[5](https://adguard-vpn.com/kb/adguard-vpn-for-linux/settings/)
[6](https://codito.in/migrate-docker-to-podman/)
[7](https://github.com/pexcn/openwrt-dns2tcp)
[8](https://manpages.ubuntu.com/manpages/xenial/man1/dns2tcpc.1.html)
[9](https://aao.fyi/bits/containers/adguard-home-setup/)
[10](https://github.com/AdguardTeam/AdGuardVPNCLI)
[11](https://dns.lookup.dog/features/udp-and-tcp)
[12](https://www.aldeid.com/wiki/Dns2tcp)
[13](https://www.ietf.org/archive/id/draft-denis-dprive-dnscrypt-02.html)
[14](https://www.reddit.com/r/podman/comments/1ndlt97/podman_networks_and_dns/)
[15](https://blog.apnic.net/2020/02/28/how-to-deploy-dot-and-doh-with-dnsdist/)
[16](https://github.com/dockur/dnsmasq)
[17](https://en.wikipedia.org/wiki/DNSCrypt)
[18](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/installing_identity_management/securing-dns-with-dot-in-idm_installing-identity-management)
[19](https://www.reddit.com/r/pihole/comments/13o582i/question_about_editing_dnsmasq_to_exclude_a/)
[20](https://www.dnscrypt.org)