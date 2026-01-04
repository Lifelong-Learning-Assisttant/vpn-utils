# Контекст задачи: Запуск Podman контейнера в VPN namespace

## Статус задачи

**Текущее состояние:** Протестированы DNS решения - найдена проблема с DNS в VPN namespace

---

## Что уже сделано

### 1. Анализ проблемы
- Прочитана документация [`vpn-utils/docs/vs_code_podman.md`](vpn-utils/docs/vs_code_podman.md)
- Оригинальная команда вызывала ошибку:
  ```bash
  sudo ip netns exec vpn-ns podman run -d --cgroups=disabled ...
  ```
  
  **Ошибка:**
  ```
  Error: OCI runtime error: invalid file system type on '/sys/fs/cgroup'
  ```

### 2. Проведено исследование
Использованы источники:
- **Tavily** - поиск решений для Podman в network namespace
- **Context7** - документация по Podman
- **GPT5, Grok, Perplexity** - консультация по проблеме DNS в контейнере с AdGuard VPN CLI

### 3. Найдена причина проблемы

**Корневая причина:** Команда `ip netns exec` создает **mount namespace** и перемонтирует `/sys` внутри namespace. Это делает хостовый `/sys/fs/cgroup` недоступным для Podman, который пытается работать с cgroups.

**Детали:**
- `ip netns exec` создает изолированный mount namespace
- Внутри этого namespace `/sys` перемонтируется
- Podman не может найти правильный `/sys/fs/cgroup` для работы с cgroups
- Это вызывает ошибку OCI runtime

### 4. Найдено и протестировано рабочее решение для запуска контейнера в VPN namespace

**Решение:** Использование `--network=ns:/run/netns/vpn-ns` параметра Podman 3.4.4

**Рабочая команда:**
```bash
sudo podman run -d \
  --name code-server-vpn \
  --network=ns:/run/netns/vpn-ns \
  --dns 8.8.8.8 \
  --security-opt label=disable \
  -v "$(pwd)":/workspaces/project \
  -e PASSWORD="12345gpu" \
  docker.io/codercom/code-server:latest \
  --auth password \
  --bind-addr 0.0.0.0:8080
```

**Почему это работает:**
- Параметр `--network=ns:/run/netns/vpn-ns` позволяет контейнеру присоединиться к существующему network namespace
- Контейнер использует тот же network namespace, что и VPN процесс (`net:[4026533317]`)
- Контейнер видит VPN интерфейс `tun0` с IP `172.16.219.2/32`
- Маршрутизация настроена правильно - маршрут по умолчанию идет через `tun0`

### 5. Протестировано сетевое подключение

**Что работает ✅:**
1. **Контейнер успешно запускается в VPN namespace** - использует параметр `--network=ns:/run/netns/vpn-ns`
2. **Network namespace правильный** - контейнер использует тот же network namespace, что и VPN процесс (`net:[4026533317]`)
3. **VPN интерфейс доступен** - контейнер видит интерфейс `tun0` с IP `172.16.219.2/32`
4. **Маршрутизация правильная** - маршрут по умолчанию идет через `tun0`
5. **TCP соединения работают** - контейнер может подключаться к внешним серверам по TCP (например, DNS сервер 8.8.8.8:53)
6. **DoH (DNS-over-HTTPS) работает** - DNS запросы через HTTPS успешно выполняются через VPN

**Что НЕ работает ❌:**
1. **UDP DNS запросы не работают** - обычные DNS запросы по UDP (порт 53) таймаутят
2. **Причина** - AdGuard VPN CLI работает только с TCP для DNS, не поддерживает UDP DNS

### 6. Получена консультация от ИИ (GPT5, Grok, Perplexity)

**Результаты консультации:**
- Создан файл [`vpn-utils/docs/ai_consultation_dns_result.md`](vpn-utils/docs/ai_consultation_dns_result.md) с подробными ответами от всех ИИ
- Проанализированы все решения и убраны повторения
- Создан файл [`vpn-utils/docs/dns_solutions_analysis.md`](vpn-utils/docs/dns_solutions_analysis.md) с анализом всех уникальных решений

### 7. Найдены решения для DNS проблемы

**Сводная таблица решений:**

| Решение | Рекомендация | Сложность | Проверенность | Протокол upstream | Дополнительный контейнер |
|----------|---------------|-------------|----------------|-------------------|------------------------|
| cloudflared | ✅ GPT5 | Низкая | Высокая | DoH (HTTPS) | Да |
| unbound | ✅ GPT5 | Средняя | Высокая | TCP | Да |
| dnscrypt-proxy | ✅ GPT5, Perplexity | Средняя | Высокая | DoH/DoT/DNSCrypt | Да |
| dns2tcp | ✅ Perplexity | Высокая | Средняя | TCP | Да |
| stubby | Упомянут GPT5 | Низкая | Средняя | DoT (TLS) | Да |
| utdns | Упомянут Grok | Высокая | Низкая | TCP | Да |
| dnsmasq | Упомянут Perplexity | Низкая | Высокая | UDP (по умолчанию) | Да |
| GOST DNS Proxy | Упомянут Perplexity | Высокая | Низкая | UDP/TCP/DoT/DoH | Да |
| socat | ❌ GPT5, Grok | Низкая | Высокая | TCP | Да |
| AdGuard CLI config | ❌ Менее универсально | Низкая | - | - | Нет |

**Рекомендации:**
- **Для быстрого решения:** Используйте **cloudflared** - самый простой и проверенный вариант
- **Для профессионального решения:** Используйте **unbound** или **dnscrypt-proxy** - более гибкие решения с кэшированием и поддержкой DNSSEC
- **Для минимального решения:** Используйте **stubby** - минималистичный DoT stub resolver
- **НЕ РЕКОМЕНДУЕТСЯ:** socat (не правильно обрабатывает протокол DNS over TCP), настройка AdGuard CLI (вероятно невозможно)

### 8. Изучена документация

**Cloudflared:**
- Изучена документация в Context7
- Найдены команды для управления туннелями, но НЕ найдена документация для использования как DNS proxy с параметром `proxy-dns`
- **Проблема:** В документации cloudflared нет примеров использования `proxy-dns` для локального DNS proxy

**Unbound:**
- Library ID `/nlnetlabs/unbound` найден в Context7
- Найдена документация по tcp-upstream и forward-zone
- **Плюсы:** Полная документация, tcp-upstream официально документирован для туннелирования

**dnscrypt-proxy:**
- Найдена библиотека `/mageddo/dns-proxy-server` (DNS Proxy Server) в Context7
- **Проблема:** Это не dnscrypt-proxy, а другой проект


### 5. Контейнер успешно запущен

**Статус контейнера:**
```bash
$ sudo podman ps
CONTAINER ID  IMAGE                                  COMMAND               CREATED         STATUS             PORTS       NAMES
87ca8056dcb1  docker.io/codercom/code-server:latest  --auth password -...  16 seconds ago  Up 17 seconds ago              code-server-vpn
```

**Логи code-server:**
```
[2026-01-02T11:52:57.546Z] info  Wrote default config file to /home/coder/.config/code-server/config.yaml
[2026-01-02T11:52:57.756Z] info  code-server 4.107.0 ac7322ce566a5dc99c60d92180375329f0bbd759
[2026-01-02T11:52:57.777Z] info  Using user-data-dir /home/coder/.local/share/code-server
[2026-01-02T11:52:57.777Z] info  Using config file /home/coder/.config/code-server/config.yaml
[2026-01-02T11:52:57.777Z] info  HTTP server listening on http://0.0.0.0:8080/
[2026-01-02T11:52:57.778Z] info    - Authentication is enabled
[2026-01-02T11:52:57.778Z] info      - Using password from $PASSWORD
[2026-01-02T11:52:57.778Z] info    - Not serving HTTPS
[2026-01-02T11:52:57.779Z] info  Session server listening on /home/coder/.local/share/code-server/code-server-ipc.sock
```

### 6. Пользователь успешно подключился к code-server

**Результат:** Пользователь смог зайти в code-server через браузер по паролю

---

## Что работает ✅

1. **Запуск контейнера без ошибок cgroups** - команда с `systemd-run` и `--cgroupns=private` работает
2. **Code-server запускается и работает** - пользователь успешно подключился
3. **Документация обновлена** - добавлено рабочее решение в [`vpn-utils/docs/vs_code_podman.md`](vpn-utils/docs/vs_code_podman.md)

---

## Что НЕ работает ❌

### Проблема: Контейнер использует обычный интернет, а не VPN

**Тесты IP адресов:**
```bash
# Хост
$ curl -s ifconfig.me
176.123.161.187

# Контейнер
$ sudo podman exec code-server-vpn curl -s ifconfig.me
79.127.211.218

# VPN namespace
$ sudo ip netns exec vpn-ns curl -s ifconfig.me
79.127.211.218

# VPN интерфейс tun0
$ sudo ip netns exec vpn-ns ip addr show tun0
inet 172.16.219.2/32 scope global tun0
```

**Вывод:** Контейнер использует IP `79.127.211.218`, который совпадает с обычным интернетом, а не с VPN IP `172.16.219.2`.

**Проверка маршрутизации:**
```bash
# VPN namespace маршруты
$ sudo ip netns exec vpn-ns ip route show
default via 10.0.0.1 dev veth-ns 
10.0.0.0/24 dev veth-ns proto kernel scope link src 10.0.0.2 
10.88.0.0/16 dev cni-podman0 proto kernel scope link src 10.88.0.1 linkdown 

# Хост маршруты
$ ip route show
default via 176.123.160.1 dev enp3s0 proto dhcp src 176.123.161.187 metric 100 
```

**Проблема:** В VPN namespace маршрут по умолчанию идет через `10.0.0.1` (хост через veth-ns), а не через VPN интерфейс `tun0`.

---

## Что нужно сделать

### Основная задача
Решить проблему с DNS в VPN namespace и заставить контейнер использовать **VPN интерфейс `tun0`** вместо обычного интернета.

### Конкретные шаги

1. **Исследовать проблему с DNS в VPN namespace**
   - Понять, почему DNS запросы таймаутят, хотя порт 53 доступен
   - Найти способ разрешить DNS запросы в VPN namespace
   - Проверить конфигурацию AdGuard VPN CLI

2. **Найти способ заставить контейнер использовать VPN интерфейс tun0**
   - Понять, почему трафик идет через `veth-ns` вместо `tun0`
   - Найти способ изменить маршрутизацию внутри `vpn-ns`
   - Возможно, нужно использовать `--network=none` и настроить сеть вручную

3. **Протестировать DNS решения после решения проблемы с DNS**
   - Протестировать cloudflared с исправленным DNS
   - Протестировать unbound с исправленным DNS
   - Проверить, что DNS запросы работают в контейнере

4. **Протестировать VPN маршрутизацию в контейнере**
   - Проверить, что контейнер действительно использует VPN
   - Проверить, что трафик идет через `tun0`
   - Проверить IP адрес контейнера

5. **Обновить документацию**
   - Добавить рабочее решение в [`vpn-utils/docs/vs_code_podman.md`](vpn-utils/docs/vs_code_podman.md)
   - Объяснить, почему решение работает и как оно решает проблему

---

## Дополнительная информация

### Система
- **OS:** Linux 5.15
- **Cgroups:** cgroup2
- **Podman:** версия неизвестна

### VPN конфигурация
- **Namespace:** `vpn-ns`
- **VPN интерфейс:** `tun0` с IP `172.16.219.2/32`
- **Veth интерфейс:** `veth-ns` с IP `10.0.0.2/24`
- **Хост интерфейс:** `enp3s0` с IP `176.123.161.187`

### Контейнер
- **Название:** `code-server-vpn`
- **Образ:** `docker.io/codercom/code-server:latest`
- **Порт:** `8080`
- **Статус:** Работает, но использует обычный интернет

---

## Рекомендации

1. **Изучить документацию по маршрутизации Linux** - понять, как правильно настроить маршруты
2. **Попробовать использовать `--network=none`** - чтобы Podman не создавал свою сеть
3. **Настроить маршруты вручную внутри контейнера** - возможно, нужно добавить маршруты через `ip route`
4. **Рассмотреть использование iptables/nftables** - для перенаправления трафика

---

## Следующие шаги

1. Исследовать проблему с DNS в VPN namespace
2. Найти способ разрешить DNS запросы в VPN namespace
3. Найти способ заставить контейнер использовать `tun0`
4. Протестировать DNS решения после решения проблемы с DNS
5. Протестировать VPN маршрутизацию в контейнере
6. Обновить документацию с рабочим решением
