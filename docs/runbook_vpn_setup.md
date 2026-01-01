# Runbook: VPN + Host-Proxy Setup (AdGuard + Dante)

Этот документ описывает пошаговую настройку сетевой архитектуры для туннелирования LLM-трафика через VPN с использованием network namespace `vpn-ns`.

---

## 1. Создание Network Namespace

Создаем изолированное сетевое пространство `vpn-ns`:

```bash
sudo ip netns add vpn-ns
sudo ip netns exec vpn-ns ip link set lo up
```

---

## 2. Настройка доступа в интернет для Namespace

Чтобы внутри namespace можно было авторизоваться в VPN и скачать обновления, создаем veth-пару и настраиваем NAT.

### 2.1. Создание veth-пары

```bash
# Создаем пару интерфейсов
sudo ip link add veth-host type veth peer name veth-ns

# Перемещаем конец veth-ns в namespace
sudo ip link set veth-ns netns vpn-ns

# Настраиваем IP на хосте
sudo ip addr add 10.0.0.1/24 dev veth-host
sudo ip link set veth-host up

# Настраиваем IP внутри namespace
sudo ip netns exec vpn-ns ip addr add 10.0.0.2/24 dev veth-ns
sudo ip netns exec vpn-ns ip link set veth-ns up

# Добавляем маршрут по умолчанию внутри namespace
sudo ip netns exec vpn-ns ip route add default via 10.0.0.1
```

### 2.2. Настройка NAT и Forwarding

Определяем имя внешнего интерфейса (например, `enp3s0`):

```bash
ip route | grep default
```

Включаем IP forwarding и настраиваем NAT:

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o enp3s0 -j MASQUERADE
```

Разрешаем форвардинг трафика:

```bash
sudo iptables -A FORWARD -s 10.0.0.0/24 -i veth-host -j ACCEPT
sudo iptables -A FORWARD -d 10.0.0.0/24 -o veth-host -m state --state RELATED,ESTABLISHED -j ACCEPT
```

### 2.3. Настройка DNS

Создаем конфигурацию DNS для namespace:

```bash
sudo mkdir -p /etc/netns/vpn-ns
echo "nameserver 8.8.8.8" | sudo tee /etc/netns/vpn-ns/resolv.conf
```

### 2.4. Проверка интернета

```bash
sudo ip netns exec vpn-ns ping -c 3 8.8.8.8
sudo ip netns exec vpn-ns ping -c 3 google.com
```

---

## 3. Установка и запуск AdGuard VPN CLI

### 3.1. Установка (если не установлен)

```bash
sudo apt update && sudo apt install -y adguardvpn-cli
```

### 3.2. Авторизация и подключение внутри namespace

```bash
# Авторизация (откроется ссылка в браузере)
sudo ip netns exec vpn-ns adguardvpn-cli login

# Подключение к VPN
sudo ip netns exec vpn-ns adguardvpn-cli connect
```

### 3.3. Проверка VPN

```bash
# Проверка интерфейса tun0
sudo ip netns exec vpn-ns ip addr show tun0

# Проверка внешнего IP (должен быть IP VPN-сервера)
sudo ip netns exec vpn-ns curl ifconfig.me

# Проверка доступа к LLM API
sudo ip netns exec vpn-ns curl -s https://api.openai.com/v1/models -H "Authorization: Bearer test" -I
```

---

## 4. Установка HostProxy (Dante)

### 4.1. Установка

```bash
sudo apt install -y dante-server
```

### 4.2. Конфигурация

Создаем файл конфигурации `/tmp/danted.conf`:

```bash
cat > /tmp/danted.conf << 'EOF'
logoutput: syslog
internal: 0.0.0.0 port = 1080
external: tun0
method: username none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
}
EOF
```

### 4.3. Запуск прокси внутри namespace

```bash
sudo ip netns exec vpn-ns /usr/sbin/danted -f /tmp/danted.conf &
```

**Примечание:** Запуск с `&` переводит процесс в фон. Для постоянной работы можно использовать `tmux` или `screen`:
```bash
# В tmux
sudo ip netns exec vpn-ns /usr/sbin/danted -f /tmp/danted.conf
```

### 4.4. Проверка работы прокси

В **новом терминале** (чтобы danted продолжал работать):

```bash
# Проверка прослушивания порта
sudo ip netns exec vpn-ns ss -tlnp | grep 1080

# Тест прокси изнутри namespace
sudo ip netns exec vpn-ns curl -v -x socks5h://127.0.0.1:1080 https://ifconfig.me
```

---

## 5. HostAccess (Проброс портов на хост)

Чтобы VS Code и контейнеры могли подключиться к прокси, пробрасываем порты из namespace на хост:
- **Порт 1080**: SOCKS5 прокси (Dante) — для Python/LLM приложений
- **Порт 1090**: HTTP прокси (Tinyproxy) — для VS Code Server

### 5.1. Установка socat (если нет)

```bash
sudo apt install -y socat
```

### 5.2. Запуск проброса портов

В **новом терминале** (чтобы danted и VPN продолжали работать):

```bash
# Проброс порта 1080 (SOCKS5 Dante)
sudo socat TCP-LISTEN:1080,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1080 &

# Проброс порта 1090 (HTTP tinyproxy)
sudo socat TCP-LISTEN:1090,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1090 &
```

**Примечание:** Запуск с `&` переводит процессы в фон. Для постоянной работы можно использовать `tmux` или `screen`:
```bash
# В tmux (два окна или одно с двумя командами)
sudo socat TCP-LISTEN:1080,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1080
sudo socat TCP-LISTEN:1090,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1090
```

### 5.3. Проверка проброса с хоста

```bash
# Проверка SOCKS5 (порт 1080)
curl -v -x socks5h://localhost:1080 https://ifconfig.me

# Проверка HTTP (порт 1090)
curl -v -x http://localhost:1090 https://ifconfig.me
```

Если обе команды вернут IP VPN-сервера — **всё готово**!

---

## 6. Интеграция с приложениями

### 6.1. Kilo CLI (Node.js)

Kilo CLI запускается **внутри namespace** с доступом к файлам проекта.

**Установка:**
```bash
# Глобальная установка (рекомендуется)
npm install -g @kilocode/cli

# Или локальная в проекте
cd /path/to/project
npm install @kilocode/cli
```

**Запуск:**
```bash
# Из папки проекта
cd /home/llm-dev/project/lifelong_learning_assistant

# Запуск внутри namespace (с доступом к файлам проекта)
sudo ip netns exec vpn-ns sudo -u $USER ./node_modules/.bin/kilocode --workspace .

# Для глобальной установки
sudo ip netns exec vpn-ns sudo -u $USER kilocode --workspace .
```

**Проверка VPN для Kilo:**
```bash
# Проверить, что Kilo идет через VPN
sudo ip netns exec vpn-ns curl ifconfig.me
```

### 6.2. VS Code Server

VS Code Server использует **HTTP прокси** (порт 1090).

В `settings.json` VS Code (на сервере):
```json
{
  "http.proxy": "http://127.0.0.1:1090",
  "http.proxyStrictSSL": false
}
```

**Примечание:** VS Code поддерживает только HTTP/HTTPS прокси, не SOCKS5. Поэтому мы используем tinyproxy на порту 1090.

### 6.3. Python-приложения

Python-приложения используют **SOCKS5 прокси** (порт 1080) для LLM-запросов:

```python
import requests

session = requests.Session()
session.proxies.update({
    "http": "socks5h://localhost:1080",
    "https": "socks5h://localhost:1080",
})

response = session.post("https://api.openai.com/v1/...", json=payload)
```

**Разделение прокси:**
- **Порт 1080 (SOCKS5)**: Python/LLM приложения, Kilo CLI
- **Порт 1090 (HTTP)**: VS Code Server, расширения VS Code

---

## 7. Отладка и проверка

### 7.1. Проверка работы Kilo

```bash
# Запуск Kilo с тестовым промптом
sudo ip netns exec vpn-ns sudo -u $USER kilocode --workspace . --mode architect --continue "Создай тестовый файл"
```

### 7.2. Проверка маршрутов

```bash
# Внутри namespace
sudo ip netns exec vpn-ns ip route show
```

### 7.3. Проверка DNS

```bash
sudo ip netns exec vpn-ns cat /etc/resolv.conf
```

### 7.4. Проверка подключения к прокси

```bash
# Проверка SOCKS5 прокси (порт 1080)
nc -zv localhost 1080
curl -v -x socks5h://localhost:1080 https://ifconfig.me

# Проверка HTTP прокси (порт 1090)
nc -zv localhost 1090
curl -v -x http://localhost:1090 https://ifconfig.me

# Проверка доступа к LLM API через SOCKS5
curl -v -x socks5h://localhost:1080 https://api.openai.com/v1/models -H "Authorization: Bearer test"
```

---

## 8. Полезные команды

### Остановка VPN

```bash
sudo ip netns exec vpn-ns adguardvpn-cli disconnect
```

### Удаление namespace

```bash
sudo ip netns del vpn-ns
```

### Просмотр логов Dante

```bash
sudo journalctl -u danted -f
```

### Поиск и управление процессами

**Проверка запущенных процессов:**
```bash
# Проверить socat (проброс порта)
ps aux | grep socat

# Проверить danted (прокси)
ps aux | grep danted

# Проверить оба процесса в namespace
sudo ip netns exec vpn-ns ps aux | grep -E 'socat|danted'
```

**Завершение процессов:**
```bash
# Убить socat
sudo pkill socat

# Убить danted
sudo pkill danted

# Убить процессы внутри namespace
sudo ip netns exec vpn-ns pkill socat
sudo ip netns exec vpn-ns pkill danted

# Убить по PID (если pkill не сработал)
sudo kill -9 <PID>
sudo ip netns exec vpn-ns kill -9 <PID>
```

**Проверка портов:**
```bash
# Проверить порт 1080 на хосте
ss -tlnp | grep 1080
lsof -i :1080

# Проверить порт 1080 внутри namespace
sudo ip netns exec vpn-ns ss -tlnp | grep 1080
sudo ip netns exec vpn-ns lsof -i :1080
```

**Перезапуск компонентов:**
```bash
# Перезапуск danted (убедитесь, что старый процесс убит)
sudo ip netns exec vpn-ns /usr/sbin/danted -f /tmp/danted.conf &

# Перезапуск tinyproxy (убедитесь, что старый процесс убит)
sudo ip netns exec vpn-ns /usr/bin/tinyproxy -c /tmp/tinyproxy.conf &

# Перезапуск socat для обоих портов (убедитесь, что старые процессы убиты)
sudo socat TCP-LISTEN:1080,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1080 &
sudo socat TCP-LISTEN:1090,bind=0.0.0.0,fork,reuseaddr TCP:10.0.0.2:1090 &
```

---

## 9. Чек-лист

- [x] `vpn-ns` создан и `lo` поднят
- [x] Интернет внутри namespace работает (ping 8.8.8.8 и google.com)
- [x] AdGuard VPN подключен (`tun0` поднят, IP VPN виден)
- [ ] Dante прокси (SOCKS5) запущен внутри namespace на порту 1080
- [ ] Tinyproxy (HTTP) запущен внутри namespace на порту 1090
- [ ] Запуск проброса порта `1080` на хост работает (SOCKS5) через socat
- [ ] Pfgecr проброса порта `1090` на хост работает (HTTP) через socat
- [ ] Kilo CLI установлен и запускается внутри namespace
- [ ] VS Code настроен на HTTP прокси (порт 1090)
- [ ] Python-модуль `llm_client` использует SOCKS5 прокси (порт 1080)

---

## 10. Примечания

- Для работы `adguardvpn-cli` внутри namespace требуется интернет (veth + NAT).
- `socks5h` (remote DNS) обязателен для предотвращения DNS-утечек.
- Проброс порта через `socat` — временное решение для теста. В продакшене лучше использовать `systemd` unit или Docker-контейнеры.
- Kilo CLI запускается внутри namespace с правами текущего пользователя для доступа к файлам проекта.
- **Важно:** Для длительной работы прокси и проброса портов используйте `tmux` или `screen`, либо настройте `systemd` unit-файлы.
- **Проверка:** После запуска всех компонентов убедитесь, что `socat`, `danted` и `tinyproxy` работают в фоне (команды `ps aux | grep socat`, `ps aux | grep danted`, `ps aux | grep tinyproxy`).
- **Разделение прокси:**
  - **Порт 1080 (SOCKS5)**: Python/LLM приложения, Kilo CLI
  - **Порт 1090 (HTTP)**: VS Code Server, расширения VS Code