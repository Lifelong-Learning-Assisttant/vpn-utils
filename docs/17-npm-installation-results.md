# Результаты установки Kilo CLI через npm

## Дата: 2026-01-06

## Проблема

При попытке установки Kilo CLI через npm возникла ошибка:

```bash
npm install -g @kilocode/cli
```

### Ошибка:

```
npm error code EACCES
npm error syscall rename
npm error path /usr/lib/node_modules/@kilocode/cli
npm error dest /usr/lib/node_modules/@kilocode/.cli-wflfevzJ
npm error errno -13
npm error Error: EACCES: permission denied, rename '/usr/lib/node_modules/@kilocode/cli' -> '/usr/lib/node_modules/@kilocode/.cli-wflfevzJ'
```

## Анализ проблемы

### Причина

Node.js и npm были установлены через NodeSource в системные директории (`/usr/lib/node_modules`). При попытке установки глобальных пакетов npm пытается писать в эти директории, но у обычного пользователя нет прав.

### Контекст

- **Node.js версия:** v22.21.0
- **npm версия:** 10.9.4
- **Метод установки:** NodeSource
- **Префикс npm:** `/usr`

## Решение

Согласно документации npm (из context7), лучшая практика - настроить пользовательскую директорию для глобальных пакетов вместо использования sudo.

### Шаги решения

1. **Создать директорию для глобальных пакетов:**

```bash
mkdir -p ~/.npm-global
```

2. **Настроить префикс npm:**

```bash
npm config set prefix '~/.npm-global'
```

3. **Добавить в PATH:**

```bash
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

4. **Установить Kilo CLI без sudo:**

```bash
npm install -g @kilocode/cli
```

## Результаты

### Успешная установка

```bash
npm install -g @kilocode/cli
```

**Вывод:**

```
added 998 packages in 23s
```

### Проверка установки

```bash
kilo --version
```

**Результат:**

```
0.19.0
```

### Проверка пути

```bash
which kilo
```

**Результат:**

```
/home/llm-dev/.npm-global/bin/kilo
```

### Проверка конфигурации npm

```bash
npm config get prefix
```

**Результат:**

```
/home/llm-dev/.npm-global
```

## Обновление скрипта run-kilo-in-vpn-ns.sh

### Проблема

Исходный скрипт проверял наличие Kilo CLI с помощью `command -v kilo`, но при запуске с sudo проверка выполнялась в контексте root, где Kilo CLI не был найден.

### Решение

Обновлённый скрипт:

1. **Получает текущего пользователя:**

```bash
CURRENT_USER=$(logname || echo $SUDO_USER)
```

2. **Определяет путь к Kilo CLI:**

```bash
USER_HOME=$(eval echo ~$CURRENT_USER)
KILO_PATH="$USER_HOME/.npm-global/bin/kilo"
```

3. **Проверяет наличие файла:**

```bash
if [ ! -f "$KILO_PATH" ]; then
    echo -e "${RED}Kilo CLI не установлен${NC}"
    exit 1
fi
```

4. **Запускает с правильным PATH:**

```bash
ip netns exec "$VPN_NS" sudo -u "$CURRENT_USER" env PATH="$USER_HOME/.npm-global/bin:$PATH" "$KILO_PATH" "$@"
```

## Тестирование

### Запуск скрипта

```bash
sudo ./vpn-utils/scripts/run-kilo-in-vpn-ns.sh --version
```

**Результат:**

```
=== Запуск Kilo CLI в network namespace vpn-ns с VPN ===

✓ VPN подключён
  IP: 79.127.211.218

✓ Kilo CLI установлен
  Версия: 0.19.0
  Путь: /home/llm-dev/.npm-global/bin/kilo

Запуск Kilo CLI...

0.19.0

=== Kilo CLI завершил работу ===
```

## Лучшие практики для установки npm пакетов на Ubuntu 22.04

### 1. Использовать nvm вместо apt

```bash
# Установка nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Перезагрузка shell
source ~/.bashrc

# Установка Node.js LTS
nvm install --lts
```

### 2. Не использовать sudo для глобальных пакетов

Настроить пользовательскую директорию:

```bash
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### 3. Проверять права доступа

```bash
npm doctor permissions
```

### 4. Использовать npx для запуска пакетов

Для npm 5.2+:

```bash
npx @kilocode/cli
```

### 5. Использовать NodeSource для системной установки

Если нужна системная установка:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

## Ссылки

- [npm Documentation - Resolving EACCES permissions errors](https://docs.npmjs.com/resolving-eacces-permissions-errors-when-installing-packages-globally)
- [npm Documentation - Downloading and installing Node.js and npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
- [npm Documentation - npm doctor](https://docs.npmjs.com/cli/v11/commands/npm-doctor)

## Вывод

Kilo CLI успешно установлен через npm в пользовательскую директорию `~/.npm-global` без использования sudo. Скрипт [`run-kilo-in-vpn-ns.sh`](../scripts/run-kilo-in-vpn-ns.sh) обновлён для работы с новой установкой и успешно протестирован.

Теперь Kilo CLI можно запускать в network namespace `vpn-ns` с VPN для работы с Gemini API.
