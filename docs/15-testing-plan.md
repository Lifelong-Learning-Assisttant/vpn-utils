# План тестирования Kilo CLI и VS Code Server в namespace vpn-ns

## Обзор

Этот документ описывает план тестирования запуска Kilo CLI и VS Code Server в network namespace `vpn-ns` с VPN.

## Предварительные требования

### 1. Проверка namespace

```bash
sudo ip netns list
```

Ожидаемый результат:
```
vpn-ns (id: 10)
```

### 2. Проверка VPN

```bash
sudo ip netns exec vpn-ns adguardvpn-cli status
```

Ожидаемый результат:
```
Connected to FRANKFURT
```

### 3. Проверка IP через VPN

```bash
sudo ip netns exec vpn-ns curl -s ifconfig.me
```

Ожидаемый результат: IP адрес из Германии (например, 79.127.211.218)

### 4. Проверка прокси

```bash
sudo ip netns exec vpn-ns curl -s -x http://127.0.0.1:1090 ifconfig.me
```

Ожидаемый результат: IP адрес из Германии

### 5. Проверка портов прокси

```bash
sudo ip netns exec vpn-ns ss -tlnp | grep -E '1080|1090'
```

Ожидаемый результат:
```
LISTEN 0  1024  0.0.0.0:1090  0.0.0.0:*  users:(("tinyproxy",pid=...,fd=...))
```

## Тестирование Kilo CLI

### 1. Запуск скрипта

```bash
sudo ./vpn-utils/scripts/run-kilo-in-vpn-ns.sh --workspace . --mode ask "Привет! Как дела?"
```

### 2. Проверка версии

```bash
sudo ip netns exec vpn-ns sudo -u $USER kilocode --version
```

Ожидаемый результат:
```
0.18.1
```

### 3. Тест с Gemini API

```bash
sudo ip netns exec vpn-ns sudo -u $USER kilocode --workspace . --mode ask "Напиши функцию на Python для вычисления факториала"
```

Ожидаемый результат:
- Kilo CLI должен запуститься
- Не должно быть ошибки "User location is not supported for the API use"
- Должен быть получен ответ от Gemini API

### 4. Тест с режимом Architect

```bash
sudo ip netns exec vpn-ns sudo -u $USER kilocode --workspace . --mode architect "Создай простой Python скрипт для hello world"
```

Ожидаемый результат:
- Kilo CLI должен запуститься в режиме Architect
- Должен быть создан файл с кодом

## Тестирование VS Code Server

### 1. Установка VS Code Server (если не установлен)

```bash
curl -fsSL https://code-server.dev/install.sh | sh
```

### 2. Запуск скрипта

```bash
sudo ./vpn-utils/scripts/run-vscode-in-vpn-ns.sh
```

### 3. Доступ к VS Code Server

После запуска скрипта, VS Code Server будет доступен по адресу:
```
http://localhost:8080
```

### 4. Тест расширений

1. Откройте VS Code Server в браузере
2. Установите расширение (например, Python)
3. Проверьте, что расширение работает
4. Проверьте, что расширение использует прокси (нет ошибок подключения)

## Диагностика проблем

### VPN не подключается

```bash
# Проверка статуса
sudo ip netns exec vpn-ns adguardvpn-cli status

# Проверка маршрутов
sudo ip netns exec vpn-ns ip route show

# Проверка интернета
sudo ip netns exec vpn-ns ping -c 3 8.8.8.8
```

### Прокси не работает

```bash
# Проверка портов
sudo ip netns exec vpn-ns ss -tlnp | grep -E '1080|1090'

# Проверка tinyproxy
sudo ip netns exec vpn-ns ps aux | grep tinyproxy
```

### Kilo CLI не работает

```bash
# Проверка версии
sudo ip netns exec vpn-ns sudo -u $USER kilocode --version

# Проверка прав доступа
sudo ip netns exec vpn-ns sudo -u $USER whoami

# Проверка доступа к файлам проекта
sudo ip netns exec vpn-ns sudo -u $USER ls -la
```

### VS Code Server не работает

```bash
# Проверка установки
which code-server

# Проверка версии
code-server --version

# Проверка порта
ss -tlnp | grep 8080
```

## Чек-лист тестирования

- [ ] Namespace `vpn-ns` существует
- [ ] VPN подключён к FRANKFURT
- [ ] IP через VPN - немецкий
- [ ] HTTP прокси работает на порту 1090
- [ ] Kilo CLI установлен
- [ ] Kilo CLI запускается в namespace
- [ ] Kilo CLI работает с Gemini API
- [ ] Kilo CLI работает в режиме Architect
- [ ] VS Code Server установлен
- [ ] VS Code Server запускается в namespace
- [ ] VS Code Server доступен в браузере
- [ ] Расширения VS Code работают

## Известные проблемы

### 1. Namespace не найден

**Проблема:** Скрипт сообщает, что namespace не существует

**Решение:** Проверьте, что namespace существует:
```bash
sudo ip netns list
```

Если namespace не существует, создайте его:
```bash
sudo ./vpn-utils/scripts/setup-vpn-ns.sh
```

### 2. VPN не подключается

**Проблема:** AdGuard VPN CLI не может подключиться

**Решение:** Проверьте, что есть маршрут по умолчанию:
```bash
sudo ip netns exec vpn-ns ip route show
```

Если маршрута нет, добавьте его:
```bash
sudo ip netns exec vpn-ns ip route add default via 10.0.0.1 dev veth-ns
```

### 3. Прокси не работает

**Проблема:** Tinyproxy не запущен

**Решение:** Запустите tinyproxy:
```bash
sudo ip netns exec vpn-ns tinyproxy -c /tmp/tinyproxy.conf &
```

### 4. Kilo CLI не видит файлы проекта

**Проблема:** Kilo CLI не может получить доступ к файлам проекта

**Решение:** Убедитесь, что вы запускаете Kilo CLI с правами пользователя:
```bash
sudo ip netns exec vpn-ns sudo -u $USER kilocode --workspace .
```

## Дополнительные команды

### Проверка всех компонентов

```bash
echo "=== Namespace ===" && \
sudo ip netns list && \
echo "" && \
echo "=== VPN Status ===" && \
sudo ip netns exec vpn-ns adguardvpn-cli status && \
echo "" && \
echo "=== IP ===" && \
sudo ip netns exec vpn-ns curl -s ifconfig.me && \
echo "" && \
echo "=== Proxy Ports ===" && \
sudo ip netns exec vpn-ns ss -tlnp | grep -E '1080|1090' && \
echo "" && \
echo "=== Kilo CLI ===" && \
which kilocode && kilocode --version && \
echo "" && \
echo "=== VS Code Server ===" && \
which code-server && code-server --version
```

### Остановка VPN

```bash
sudo ip netns exec vpn-ns adguardvpn-cli disconnect
```

### Перезапуск VPN

```bash
sudo ip netns exec vpn-ns adguardvpn-cli disconnect
sudo ip netns exec vpn-ns adguardvpn-cli connect -l FRANKFURT
```

## Следующие шаги

После успешного тестирования:

1. Создать systemd unit файлы для автоматического запуска VPN и прокси
2. Создать systemd unit файл для VS Code Server
3. Настроить автоматический проброс портов на хост
4. Создать скрипт для быстрого запуска Kilo CLI
5. Документировать процесс для других пользователей

## Контакты

Если возникли проблемы, проверьте:
- [`vpn-utils/docs/runbook_vpn_setup.md`](runbook_vpn_setup.md) - Подробное руководство по настройке
- [`vpn-utils/docs/adguard_vpn_setup.md`](adguard_vpn_setup.md) - Справочник команд AdGuard VPN
- [`vpn-utils/docs/14-final-architecture-plan.md`](14-final-architecture-plan.md) - Итоговая архитектура
