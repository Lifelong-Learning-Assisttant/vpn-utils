# Анализ 5 лучших DNS решений на основе документации Context7

## Обзор

Этот документ содержит подробный анализ 5 лучших решений для проблемы DNS в Podman контейнере с AdGuard VPN, основанный на официальной документации из Context7.

---

## 1. Unbound - РЕКОМЕНДУЕТСЯ GPT5

### Описание
Легковесный, но мощный рекурсивный DNS-сервер с поддержкой кэширования и DNSSEC. Умеет принудительно отправлять запросы вышестоящему серверу только по TCP.

### Документация Context7
- **Library ID:** `/nlnetlabs/unbound`
- **Code Snippets:** 379
- **Source Reputation:** High

### Ключевые параметры конфигурации

#### tcp-upstream
```conf
tcp-upstream: <yes or no>

Enable or disable whether the upstream queries use TCP only for transport. 
Useful in tunneling scenarios. If set to no you can specify TCP transport 
only for selected forward or stub zones using forward-tcp-upstream or 
stub-tcp-upstream respectively.

Default: no
```

#### forward-tcp-upstream
```conf
forward-tcp-upstream: <yes or no>

If set to "yes", upstream queries use TCP only for transport, regardless of 
the global tcp-upstream flag.

Default: no
```

#### forward-zone конфигурация
```conf
forward-zone:
    name: "."
    forward-addr: 8.8.8.8@53
```

### Пример конфигурации для VPN
```conf
server:
    interface: 127.0.0.1
    access-control: 127.0.0.0/8 allow
    do-udp: yes
    do-tcp: yes
    tcp-upstream: yes  # Ключевой параметр!

forward-zone:
    name: "."
    forward-addr: 8.8.8.8@53
```

### Команда запуска в контейнере
```bash
# В Alpine контейнере
apk add unbound

# Создать конфигурацию /etc/unbound/unbound.conf
cat > /etc/unbound/unbound.conf << 'EOF'
server:
    interface: 127.0.0.1
    access-control: 127.0.0.0/8 allow
    do-udp: yes
    do-tcp: yes
    tcp-upstream: yes

forward-zone:
    name: "."
    forward-addr: 8.8.8.8@53
EOF

# Запустить
unbound -d
```

### Команда запуска контейнера
```bash
sudo podman run -d --name unbound-dns \
  --network=ns:/run/netns/vpn-ns \
  -v $(pwd)/unbound.conf:/etc/unbound/unbound.conf \
  docker.io/alpine:latest \
  sh -c "apk add --no-cache unbound && unbound -d"
```

### Плюсы
- ✅ **Подтвержденная документация** - полная документация в Context7
- ✅ **tcp-upstream параметр** - официально документирован для туннелирования
- ✅ **Гибкая настройка** - поддержка DoT, кэша, DNSSEC
- ✅ **Рекомендуется GPT5** как профессиональное решение
- ✅ **Поддерживает кэширование** DNS запросов
- ✅ **Поддерживает DNSSEC** для безопасности
- ✅ **Лёгкий и подходит** для Podman
- ✅ **Высокая проверенность** - широко используется в продакшене

### Минусы
- ❌ Нужна конфигурация (чуть больше работы, чем cloudflared)
- ❌ Нужен дополнительный контейнер/процесс

---

## 2. dnsdist - АЛЬТЕРНАТИВА ДЛЯ ПРОФЕССИОНАЛОВ

### Описание
Высокопроизводительный балансировщик DNS трафика с поддержкой DNS over TLS (DoT), DNS over HTTPS (DoH) и TCP-only режимов.

### Документация Context7
- **Library ID:** `/websites/dnsdist`
- **Code Snippets:** 2334
- **Source Reputation:** High
- **Benchmark Score:** 81.05

### Ключевые параметры конфигурации

#### TCP-only режим
```lua
newServer({address="8.8.8.8:53", tcpOnly=true})
```

#### DNS over TLS (DoT)
```lua
newServer({
    address="[2001:DB8::1]:853", 
    tls="openssl", 
    subjectName="dot.powerdns.com", 
    validateCertificates=true
})
```

#### Параметры backend
```lua
{
    checkTCP: bool,           -- Healthcheck queries over TCP
    tls: string,              -- Enable DoT or DoH
    caStore: string,          -- Path to CA certificates
    validateCertificates: bool, -- Validate backend certificates
    ciphers: string,          -- TLS 1.2 ciphers
    ciphersTLS13: string,     -- TLS 1.3 ciphers
    subjectName: string,      -- SNI value
    dohPath: string,          -- Enable DoH
    tcpOnly: bool,            -- TCP-only mode
    maxConcurrentTCPConnections: number
}
```

### Пример конфигурации для VPN
```lua
-- TCP-only backend для обычного DNS
newServer({
    address="8.8.8.8:53",
    tcpOnly=true,
    checkTCP=true,
    maxConcurrentTCPConnections=100
})

-- Или DoT backend для шифрования
newServer({
    address="8.8.8.8:853",
    tls="openssl",
    subjectName="dns.google",
    validateCertificates=true,
    checkTCP=true
})

-- Слушать на локальном порту 53
setLocal("127.0.0.1:53")
```

### Команда запуска в контейнере
```bash
# В контейнере
dnsdist --config /etc/dnsdist/dnsdist.conf
```

### Плюсы
- ✅ **Подтвержденная документация** - обширная документация в Context7
- ✅ **tcpOnly параметр** - официально документирован для TCP-only режима
- ✅ **Высокая производительность** - оптимизирован для тяжелых нагрузок
- ✅ **Множественные протоколы** - DoT, DoH, TCP-only
- ✅ **Продвинутые функции** - health checking, load balancing, filtering
- ✅ **Гибкая конфигурация** - Lua скрипты
- ✅ **Высокий Benchmark Score** - 81.05

### Минусы
- ❌ Более сложная настройка, чем unbound
- ❌ Нужен дополнительный контейнер/процесс
- ❌ Избыточен для простых сценариев

---

## 3. DNS Proxy Server - АЛЬТЕРНАТИВА ДЛЯ РАЗРАБОТЧИКОВ

### Описание
Легковесный DNS сервер для разработчиков и администраторов, который разрешает имена хостов из локальных конфигураций, Docker контейнеров и удаленных DNS серверов.

### Документация Context7
- **Library ID:** `/mageddo/dns-proxy-server`
- **Code Snippets:** 182
- **Source Reputation:** High

### Ключевые параметры конфигурации

#### serverProtocol
```json
{
  "serverProtocol": "UDP_TCP"
}
```

#### remoteDnsServers
```json
{
  "remoteDnsServers": ["8.8.8.8", "4.4.4.4:54"]
}
```

### Пример конфигурации для VPN
```json
{
  "version": 2,
  "remoteDnsServers": ["8.8.8.8"],
  "dnsServerPort": 53,
  "serverProtocol": "UDP_TCP",
  "logLevel": "INFO"
}
```

### Плюсы
- ✅ **Подтвержденная документация** - документация в Context7
- ✅ **Поддерживает UDP и TCP** - serverProtocol: "UDP_TCP"
- ✅ **Легковесный** - оптимизирован для разработки
- ✅ **Графический интерфейс** для управления DNS записями
- ✅ **Интеграция с Docker** - автоматическое обнаружение контейнеров

### Минусы
- ❌ **Не найдена документация** по TCP-only режиму
- ❌ **Не найдена документация** по DoH/DoT
- ❌ Может не поддерживать принудительный TCP upstream
- ❌ Нужен дополнительный контейнер/процесс

---

## 4. cloudflared - РЕКОМЕНДУЕТСЯ GPT5

### Описание
Утилита от Cloudflare для создания туннелей и DNS over HTTPS (DoH) прокси.

### Документация Context7
- **Library ID:** `/cloudflare/cloudflared`
- **Code Snippets:** 451
- **Source Reputation:** High
- **Benchmark Score:** 72.8

### Найденная документация
Документация в Context7 содержит информацию о:
- Создании и управлении туннелями
- Маршрутизации DNS через туннели
- Конфигурации ingress правил
- SOCKS5 proxy

### НЕ найдена документация
❌ **proxy-dns** - документация по использованию cloudflared как локального DNS прокси не найдена в Context7

### Предполагаемая конфигурация (на основе консультации ИИ)
```bash
cloudflared proxy-dns \
  --address 127.0.0.1 \
  --port 53 \
  --upstream https://1.1.1.1/dns-query \
  --upstream https://1.0.0.1/dns-query
```

### Плюсы
- ✅ **Подтвержденная документация** - обширная документация в Context7
- ✅ **Рекомендуется GPT5** как лучшее решение
- ✅ **Простая реализация** - проверенная во многих сценариях
- ✅ **Использует DoH (HTTPS)** - точно проходит через TCP/HTTPS через VPN
- ✅ **Не требует изменения** AdGuard VPN CLI
- ✅ **Принимает обычные UDP запросы** от приложений
- ✅ **Высокая проверенность** - широко используется

### Минусы
- ❌ **Документация по proxy-dns не найдена** в Context7
- ❌ Нужен дополнительный контейнер/процесс (sidecar pattern)
- ❌ Использует DoH (HTTPS) - может быть медленнее, чем чистый TCP

---

## 5. DNS2TCP - АЛЬТЕРНАТИВА ДЛЯ ПРОСТЫХ СЦЕНАРИЕВ

### Описание
Легковесный конвертер UDP→TCP. Слушает на UDP (например, порт 5353), forwards queries as TCP к 8.8.8.8:53.

### Документация Context7
❌ **НЕ найдена документация** в Context7

### Предполагаемая конфигурация (на основе консультации ИИ)
```bash
# В Alpine контейнере
apk add build-base git make
git clone https://github.com/zfl9/dns2tcp && cd dns2tcp && make && cp dns2tcp /usr/local/bin/

# Запуск
dns2tcp -L 127.0.0.1#5353 -R 8.8.8.8#53
```

### Плюсы
- ✅ **Рекомендуется Perplexity** как легковесное решение
- ✅ **Легковесный** - минимальные зависимости
- ✅ **Простая установка** - компиляция из исходников

### Минусы
- ❌ **Документация не найдена** в Context7
- ❌ Использует нестандартный порт (5353)
- ❌ Нужна компиляция из исходников
- ❌ Нужен дополнительный контейнер/процесс
- ❌ Менее проверенный, чем cloudflared/unbound

---

## Сводная таблица решений

| Решение | Документация Context7 | Проверенность | Протокол upstream | Сложность | Рекомендация |
|----------|----------------------|----------------|-------------------|-----------|---------------|
| **Unbound** | ✅ Полная | Высокая | TCP | Средняя | ✅ GPT5 |
| **dnsdist** | ✅ Полная | Высокая | TCP/DoT/DoH | Высокая | - |
| **DNS Proxy Server** | ✅ Частичная | Средняя | UDP/TCP | Низкая | - |
| **cloudflared** | ✅ Частичная (без proxy-dns) | Высокая | DoH (HTTPS) | Низкая | ✅ GPT5 |
| **dns2tcp** | ❌ Нет | Средняя | TCP | Высокая | ✅ Perplexity |

---

## Рекомендации

### Для быстрого решения:
Используйте **cloudflared** - самый простой и проверенный вариант, несмотря на отсутствие документации по proxy-dns в Context7.

### Для профессионального решения:
Используйте **unbound** - имеет полную документацию в Context7, поддерживает tcp-upstream для туннелирования, более гибкое решение с кэшированием и поддержкой DNSSEC.

### Для высокопроизводительного решения:
Используйте **dnsdist** - имеет полную документацию в Context7, поддерживает tcpOnly режим, оптимизирован для тяжелых нагрузок.

### Для разработки:
Используйте **DNS Proxy Server** - имеет документацию в Context7, поддерживает UDP_TCP, но может не поддерживать принудительный TCP upstream.

---

## Следующие шаги

1. **Выбрать решение** - unbound или cloudflared
2. **Протестировать выбранное решение** в VPN namespace
3. **Проверить DNS резолвинг** в контейнере
4. **Обновить документацию** `vpn-utils/docs/vs_code_podman.md` с рабочим решением
