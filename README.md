# VPN Utilities

Набор утилит и документации для настройки VPN в проекте.

## Структура

- `fix-vpn-routes.sh` - скрипт для автоматической настройки VPN маршрутов
- `docs/` - документация по VPN настройке

## Документация

- [AdGuard VPN Setup](docs/adguard_vpn_setup.md) - инструкция по настройке AdGuard VPN
- [Network Architecture](docs/network_architecture.md) - описание сетевой архитектуры
- [Open Router VPN](docs/open_router_vpn.md) - настройка VPN для Open Router

## Использование

```bash
# Запуск скрипта настройки маршрутов
./fix-vpn-routes.sh

# Просмотр документации
cat docs/adguard_vpn_setup.md
```

## Интеграция с основным проектом

Этот репозиторий подключен как git submodule к основному проекту.
Для обновления используйте:

```bash
git submodule update --init --recursive
cd vpn-utils
git pull origin main