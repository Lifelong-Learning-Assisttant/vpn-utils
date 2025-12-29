# Быстрый старт: Split Routing

## Цель

Иметь рабочую конфигурацию, где:
- ✅ OpenAI и OpenRouter доступны через VPN
- ✅ GitHub, Docker, PyPI работают напрямую (быстро)
- ✅ SSH всегда доступен
- ✅ VPN трафик расходуется только на нейросети (4 ГБ хватит)
- ✅ Контейнеры и pip не трогают VPN-трафик

---

## 1. Подключение VPN

```bash
# 1. Подключить VPN к Германии
adguardvpn-cli connect -l FRANKFURT

# 2. ВАЖНО: Отключить автоматическую смену DNS
adguardvpn-cli config set-change-system-dns off

# 3. Проверить статус
adguardvpn-cli status
```

**Почему `set-change-system-dns off`?**
- Мы управляем маршрутизацией вручную через ip rules
- Автоматическая смена DNS мешает split routing

---

## 2. Настройка split routing

```bash
# Запустить скрипт (требует sudo)
sudo ./setup_split_routing.sh
```

**Что делает скрипт:**
- ✅ Добавляет маршруты для Cloudflare (OpenAI) → VPN
- ✅ Добавляет маршруты для OpenRouter → VPN
- ✅ Сохраняет SSH правило (table 100) → провайдер
- ✅ Все остальное → провайдер

---

## 3. Проверка работы

```bash
# Запустить тесты
./test_split_routing.sh
```

**Или вручную:**

```bash
# 1. Проверить VPN
adguardvpn-cli status

# 2. Проверить маршруты
ip route get 162.159.140.245  # OpenAI → должен быть tun0
ip route get 140.82.121.3     # GitHub → должен быть enp3s0

# 3. Проверить доступность
curl -s -o /dev/null -w "%{http_code}" https://openrouter.ai/api/v1/models  # Должен быть 200
curl -s -o /dev/null -w "%{http_code}" https://api.github.com/user          # Должен быть 401 (требует токен)
```

---

## 4. Отключение VPN

```bash
# 1. Отключить VPN
adguardvpn-cli disconnect

# 2. Очистить правила (опционально)
sudo ip rule del from 176.123.161.187 table 880 2>/dev/null || true
sudo ip route flush table 880 2>/dev/null || true
```

---

## Диагностика сети

### Полная диагностика
```bash
./test_split_routing.sh
```

### Вручную
```bash
# 1. VPN статус
adguardvpn-cli status
adguardvpn-cli config show | grep -E "DNS|system"

# 2. Маршруты
ip route get 162.159.140.245  # OpenAI
ip route get 8.6.112.6        # OpenRouter
ip route get 140.82.121.3     # GitHub
ip route get 100.49.175.172   # Docker

# 3. Policy routing
ip rule show | grep "176.123.161.187"
ip route show table 100  # SSH
ip route show table 880  # VPN

# 4. Проверка DNS
dig google.com +short
dig openrouter.ai +short
```

---

## Troubleshooting

### OpenAI/OpenRouter не работают
```bash
# 1. Проверить VPN
adguardvpn-cli status

# 2. Проверить маршруты
ip route get 162.159.140.245 | grep tun0
ip route get 8.6.112.6 | grep tun0

# 3. Перезапустить split routing
sudo ./setup_split_routing.sh
```

### GitHub/Docker медленные
```bash
# Проверить маршруты (должны идти через enp3s0)
ip route get 140.82.121.3
ip route get 100.49.175.172

# Если идут через tun0 — ошибка в настройках
# Перезапустите split routing
sudo ./setup_split_routing.sh
```

### SSH отключается
```bash
# Проверить table 100
ip rule show | grep "lookup 100"
ip route show table 100

# Должно быть:
# 30754: from 176.123.161.187 lookup 100
# default via 176.123.160.1 dev enp3s0 table 100
```

### Apt не работает
```bash
# Проверить DNS
dig google.com +short

# Перезапустить systemd-resolved
sudo systemctl restart systemd-resolved
```

---

## Как это работает

### Схема
```
Весь трафик → Policy Routing
├── OpenAI/OpenRouter → table 880 → VPN (tun0)
├── GitHub/Docker/PyPI → провайдер (enp3s0)
└── SSH → table 100 → провайдер (enp3s0)
```

### Ключевые моменты
1. **`set-change-system-dns off`** — отключаем автоматику
2. **Policy routing** — делим трафик по IP-диапазонам
3. **Table 880** — VPN для OpenAI/OpenRouter (только трафик LLM)
4. **Table 100** — SSH защищен от VPN
5. **Экономия** — Docker/PyPI/GitHub не расходуют VPN-трафик

---

## См. также

- [Архитектура сети](network_architecture.md) — теория и схемы
- [Справочник команд](adguard_vpn_setup.md) — все команды AdGuard VPN
- [Базовые настройки DNS](dns_base.md) — восстановление DNS

---

**Дата:** 2025-12-29  
**Статус:** ✅ Split routing работает