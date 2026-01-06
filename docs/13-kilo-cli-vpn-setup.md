# Kilo CLI в VPN сети

## Обзор

Документ описывает настройку и использование Kilo CLI в сетевом namespace VPN контейнера для обеспечения доступа к Gemini API из регионов, где он недоступен.

## Проблема

Gemini API возвращает ошибку "User location is not supported for the API use" при попытке доступа из России. Необходимо использовать VPN для обхода географических ограничений.

## Решение

Kilo CLI запускается как процесс на хосте в сетевом namespace VPN контейнера с использованием прокси для всех сетевых запросов.

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                    Хост-машина                          │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  VPN Контейнер (adguardvpn-cli + tinyproxy)     │  │
│  │  - tun0: 172.16.219.2/32                        │  │
│  │  - HTTP прокси: 127.0.0.1:1090                  │  │
│  │  - VPN IP: 156.146.33.99 (Франкфурт)            │  │
│  └──────────────────────────────────────────────────┘  │
│                    ↑                                   │
│                    │ nsenter -n                        │
│                    │ (сетевой namespace)                │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Kilo CLI (Node.js процесс)                     │  │
│  │  - HTTP_PROXY=http://127.0.0.1:1090             │  │
│  │  - HTTPS_PROXY=http://127.0.0.1:1090           │  │
│  │  - /etc/resolv.conf → 127.0.0.11 (VPN DNS)     │  │
│  └──────────────────────────────────────────────────┘  │
│                    ↓                                   │
│              /var/run/docker.sock                       │
│                    ↓                                   │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Docker Контейнеры (управление через Kilo CLI)  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Компоненты

### VPN Контейнер

- **adguardvpn-cli**: VPN клиент для подключения к серверам AdGuard VPN
- **tinyproxy**: HTTP прокси сервер на порту 1090
- **VPN DNS**: 127.0.0.11 (Docker DNS)

### Kilo CLI

- **Путь**: `./node_modules/@kilocode/cli/index.js`
- **Версия**: 0.18.1
- **Переменные окружения**:
  - `HTTP_PROXY=http://127.0.0.1:1090`
  - `HTTPS_PROXY=http://127.0.0.1:1090`
  - `ALL_PROXY=socks5h://127.0.0.1:1080`
  - `NO_PROXY=localhost,127.0.0.1`

## Скрипты

### 1. Запуск Kilo CLI в VPN сети

**Скрипт**: [`vpn-utils/scripts/run-kilo-in-vpn.sh`](../scripts/run-kilo-in-vpn.sh)

```bash
./vpn-utils/scripts/run-kilo-in-vpn.sh [аргументы Kilo CLI]
```

**Примеры**:

```bash
# Запуск Kilo CLI в интерактивном режиме
./vpn-utils/scripts/run-kilo-in-vpn.sh

# Запуск с конкретным режимом
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code

# Запуск с автоподтверждением
./vpn-utils/scripts/run-kilo-in-vpn.sh --yolo
```

**Что делает скрипт**:
1. Проверяет, что VPN контейнер запущен
2. Проверяет наличие Kilo CLI
3. Создаёт временный resolv.conf с VPN DNS
4. Запускает Kilo CLI в сетевом namespace VPN контейнера
5. Подменяет /etc/resolv.conf для использования VPN DNS
6. Устанавливает переменные окружения для прокси

### 2. Тестирование Kilo CLI с прокси

**Скрипт**: [`vpn-utils/scripts/test-kilo-with-proxy.sh`](../scripts/test-kilo-with-proxy.sh)

```bash
./vpn-utils/scripts/test-kilo-with-proxy.sh
```

**Проверяет**:
1. Версию Kilo CLI
2. IP адрес через Node.js с прокси
3. Доступ к docker.sock

### 3. Проверка IP адреса в VPN сети

**Скрипт**: [`vpn-utils/scripts/check-vpn-ip.sh`](../scripts/check-vpn-ip.sh)

```bash
./vpn-utils/scripts/check-vpn-ip.sh
```

**Проверяет**:
1. IP адрес через ifconfig.me
2. IP адрес через api.ipify.org
3. DNS резолвинг
4. Сетевые интерфейсы

## Результаты тестирования

### ✅ Успешно протестировано

| Тест | Результат | Детали |
|------|-----------|--------|
| VPN контейнер | ✅ Работает | IP: 156.146.33.99 (Франкфурт) |
| HTTP прокси | ✅ Работает | Порт 1090 |
| Node.js с прокси | ✅ Работает | IP: 156.146.33.99 |
| Kilo CLI версия | ✅ Работает | Версия 0.18.1 |
| DNS резолвинг | ✅ Работает | Через VPN DNS (127.0.0.11) |
| Доступ к docker.sock | ✅ Работает | Полный доступ |

### Примеры вывода

```bash
$ ./vpn-utils/scripts/test-kilo-with-proxy.sh
=== Тестирование Kilo CLI с прокси в VPN сети ===

✓ VPN контейнер найден (PID: 2973249)
✓ Временный resolv.conf создан

Тест 1: Проверка версии Kilo CLI с прокси...
✓ Kilo CLI версия: 0.18.1

Тест 2: Проверка IP адреса через Node.js с прокси...
✓ IP адрес через Node.js: {"ip":"156.146.33.99"}

Тест 3: Проверка доступа к docker.sock...
✓ Доступ к docker.sock есть:
NAMES                              STATUS
vpn                                Up About an hour
llm-tester-api                     Up 8 days
agent_service-agent_dev-1          Up 8 days
web_ui_service-frontend-dev        Up 10 days
```

## Преимущества подхода

| Аспект | Dev Container (старый) | Новый подход (netns + прокси) |
|--------|------------------------|------------------------------|
| Доступ к docker.sock | ❌ Нет | ✅ Полный доступ |
| Управление контейнерами | ❌ Нельзя | ✅ Можно |
| Сетевой трафик | ✅ Через VPN | ✅ Через VPN |
| DNS резолвинг | ✅ Через VPN | ✅ Через VPN |
| Node.js прокси | ❌ Не используется | ✅ Используется |
| Gemini API | ❌ Ошибка локации | ✅ Работает |

## Использование

### Базовое использование

```bash
# Запуск Kilo CLI в VPN сети
./vpn-utils/scripts/run-kilo-in-vpn.sh

# Запуск с конкретным режимом
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code

# Запуск с автоподтверждением
./vpn-utils/scripts/run-kilo-in-vpn.sh --yolo
```

### Примеры задач

```bash
# Создание нового файла
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code "Создай файл test.py с функцией hello world"

# Рефакторинг кода
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code "Отрефактори функцию main в app.py"

# Запуск контейнера
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code "Запусти docker контейнер с nginx"

# Управление контейнерами
./vpn-utils/scripts/run-kilo-in-vpn.sh -m code "Останови все контейнеры с именем test"
```

## Устранение неполадок

### Проблема: "Permission denied" при запуске

**Решение**: Убедитесь, что скрипт имеет права на выполнение:

```bash
chmod +x vpn-utils/scripts/run-kilo-in-vpn.sh
```

### Проблема: "VPN контейнер не найден"

**Решение**: Запустите VPN контейнер:

```bash
# В директории vpn-utils
cd vpn-utils
# Запустите VPN контейнер (зависит от вашей конфигурации)
```

### Проблема: "Kilo CLI не найден"

**Решение**: Убедитесь, что вы находитесь в корне проекта и node_modules установлен:

```bash
# Установка зависимостей
npm install

# Проверка наличия Kilo CLI
ls -la ./node_modules/@kilocode/cli/index.js
```

### Проблема: "Не удалось подключиться к прокси"

**Решение**: Проверьте, что tinyproxy работает в VPN контейнере:

```bash
# Проверка процесса tinyproxy
docker exec vpn ps aux | grep tinyproxy

# Проверка порта
docker exec vpn netstat -tuln | grep 1090
```

### Проблема: "DNS резолвинг не работает"

**Решение**: Проверьте, что /etc/resolv.conf подменяется корректно:

```bash
# Проверка DNS в VPN контейнере
docker exec vpn cat /etc/resolv.conf

# Проверка DNS через прокси
curl -x http://127.0.0.1:1090 https://api.ipify.org?format=json
```

## Следующие шаги

1. **Автоматизация**: Создать systemd service для автоматического запуска Kilo CLI в VPN сети
2. **Мониторинг**: Добавить логирование и мониторинг для отслеживания работы прокси
3. **Альтернативные прокси**: Рассмотреть использование других прокси серверов (например, glider)
4. **Оптимизация**: Настроить кэширование DNS для ускорения резолвинга

## Связанные документы

- [`01-architecture-concept.md`](./01-architecture-concept.md) - Общая архитектура проекта
- [`08-testing-plan.md`](./08-testing-plan.md) - План тестирования
- [`12-test-summary.md`](./12-test-summary.md) - Итоговый отчёт о тестировании
- [`10-code-server-approach.md`](./10-code-server-approach.md) - Работа с code-server в новой архитектуре

## Заключение

Новый подход с использованием сетевого namespace VPN контейнера и прокси полностью решает проблему доступа к Gemini API из России. Kilo CLI может управлять docker контейнерами и использовать VPN для сетевого трафика, при этом сохраняя все преимущества VPN и обеспечивая полный доступ к docker.sock.
