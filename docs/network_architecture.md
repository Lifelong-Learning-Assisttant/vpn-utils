# Сетевая архитектура: Split Routing

## Проблема

### Географические ограничения
OpenRouter и OpenAI блокируют доступ из российских IP-адресов:
```
OpenRouter: Error code: 403 - {'error': {'message': 'Access denied: This service is not available in your region.'}}
OpenAI: Error code: 403 - {'error': {'code': 'unsupported_country_region_territory', 'message': 'Country, region, or territory not supported'}}
```

### Проблема с CDN
GitHub, Docker, PyPI, OpenRouter и OpenAI используют CDN (Cloudflare, Fastly) с часто меняющимися IP-адресами.

### Проблема с трафиком VPN
- **VPN трафик ограничен** (AdGuard Free — 4 ГБ/месяц)
- **Docker контейнеры** быстро расходуют трафик
- **PyPI/GitHub** передают гигабайты данных
- **Весь трафик через VPN** = быстрое исчерпание лимита

### Попытки решить:
1. ❌ **Список IP для OpenRouter/OpenAI** — не работает, IP CDN меняются
2. ❌ **Весь трафик через VPN** — 4 ГБ быстро кончаются, Docker/PyPI тормозят
3. ✅ **Split routing по диапазонам** — только нейросети через VPN, остальное напрямую

---

## Решение: Split Routing

### Принцип работы
Трафик делится по **IP-диапазонам** через policy routing:
- **OpenAI/OpenRouter** → VPN (Frankfurt)
- **GitHub/Docker/PyPI** → напрямую (провайдер)
- **SSH** → напрямую (провайдер)

### Схема
```
┌─────────────────────────────────────────────────────┐
│ Ваш сервер: 176.123.161.187                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │ Policy Routing (ip rules)                    │  │
│  │                                              │  │
│  │  from 176.123.161.187 to 8.6.112.0/24        │  │
│  │  from 176.123.161.187 to 8.47.69.0/24        │  │
│  │  from 176.123.161.187 to 173.245.48.0/20     │  │
│  │  ... (все Cloudflare диапазоны)              │  │
│  │  → table 880                                 │  │
│  │                                              │  │
│  │  from 176.123.161.187 lookup 100             │  │
│  │  → table 100                                 │  │
│  └──────────────────────────────────────────────┘  │
│                    │                    │           │
│                    ▼                    ▼           │
│            ┌──────────────┐      ┌──────────┐      │
│            │ Table 880    │      │ Table 100│      │
│            │ (VPN)        │      │ (Direct) │      │
│            │              │      │          │      │
│            │ tun0         │      │ enp3s0   │      │
│            │              │      │          │      │
│            │ OpenAI       │      │ GitHub   │      │
│            │ OpenRouter   │      │ Docker   │      │
│            │              │      │ PyPI     │      │
│            │              │      │ SSH      │      │
│            └──────────────┘      └──────────┘      │
└─────────────────────────────────────────────────────┘
```

---

## Компоненты системы

### 1. AdGuard VPN CLI
```bash
adguardvpn-cli connect -l FRANKFURT
adguardvpn-cli config set-change-system-dns off  # ВАЖНО!
```

**Почему `off`?**
- Мы управляем маршрутизацией вручную через ip rules
- Автоматическая смена DNS мешает split routing

### 2. Policy Routing (ip rules + ip route)

#### Table 100 (SSH + провайдер)
```bash
ip rule add from 176.123.161.187 lookup 100
ip route add default via 176.123.160.1 dev enp3s0 table 100
```
**Что делает:** Весь трафик ОТ сервера идет через провайдера (SSH всегда работает)

#### Table 880 (VPN)
```bash
# Cloudflare диапазоны (OpenAI)
for range in 173.245.48.0/20 103.21.244.0/22 ...; do
    ip rule add from 176.123.161.187 to $range table 880
    ip route add $range dev tun0 table 880
done

# OpenRouter диапазоны
ip rule add from 176.123.161.187 to 8.6.112.0/24 table 880
ip rule add from 176.123.161.187 to 8.47.69.0/24 table 880
ip route add 8.6.112.0/24 dev tun0 table 880
ip route add 8.47.69.0/24 dev tun0 table 880
```
**Что делает:** Трафик К OpenAI/OpenRouter идет через VPN

### 3. systemd-resolved
Работает в стандартном режиме, без изменений.

---

## IP-диапазоны

### OpenAI (через Cloudflare)
```
173.245.48.0/20
103.21.244.0/22
103.22.200.0/22
103.31.4.0/22
141.101.64.0/18
108.162.192.0/18
190.93.240.0/20
188.114.96.0/20
197.234.240.0/22
198.41.128.0/17
162.158.0.0/15
104.16.0.0/13
104.24.0.0/14
172.64.0.0/13
131.0.72.0/22
```

### OpenRouter
```
8.6.112.0/24
8.47.69.0/24
```

---

## Преимущества подхода

### ✅ Экономия трафика VPN
- **Только нейросети** через VPN (OpenAI/OpenRouter)
- **Docker/PyPI/GitHub** работают напрямую
- **4 ГБ хватит** только для общения с LLM
- **Контейнеры не расходуют** VPN трафик

### ✅ Надежность
- Не зависит от CDN
- IP-диапазоны Cloudflare редко меняются
- OpenRouter использует статические IP

### ✅ Скорость
- GitHub/Docker/PyPI работают напрямую (максимальная скорость)
- Нет задержек VPN для нетребовательных сервисов

### ✅ Простота
- Два скрипта: настройка и тестирование
- Не требует ручного обновления списков IP

### ✅ Стабильность
- SSH всегда работает (table 100)
- VPN падение не ломает доступ к серверу

---

## Скрипты

### setup_split_routing.sh
```bash
sudo ./setup_split_routing.sh
```
Создает все правила и маршруты.

### test_split_routing.sh
```bash
./test_split_routing.sh
```
Проверяет:
- Маршрутизацию для каждого сервиса
- Доступность API
- Статус VPN
- Policy routing

---

## Диагностика

### Проверка маршрутов
```bash
# OpenAI → через VPN
ip route get 162.159.140.245
# Должно быть: dev tun0 table 880

# GitHub → напрямую
ip route get 140.82.121.3
# Должно быть: via 176.123.160.1 dev enp3s0

# SSH → напрямую
ip route get 176.123.161.187
# Должно быть: dev lo table local
```

### Проверка правил
```bash
ip rule show | grep "176.123.161.187"
```
Должно показать:
```
30737: from 176.123.161.187 to 8.47.69.0/24 lookup 880
30738: from 176.123.161.187 to 8.6.112.0/24 lookup 880
30739: from 176.123.161.187 to 131.0.72.0/22 lookup 880
...
30754: from 176.123.161.187 lookup 100
```

### Проверка доступности
```bash
# OpenAI (должен быть 401 — требует API ключ)
curl -s -o /dev/null -w "%{http_code}" https://api.openai.com/v1/models

# OpenRouter (должен быть 200)
curl -s -o /dev/null -w "%{http_code}" https://openrouter.ai/api/v1/models

# GitHub (должен быть 401 — требует токен)
curl -s -o /dev/null -w "%{http_code}" https://api.github.com/user
```

---

## Troubleshooting

### OpenAI не работает
```bash
# 1. Проверить VPN
adguardvpn-cli status

# 2. Проверить маршруты
ip route get 162.159.140.245 | grep tun0

# 3. Перезапустить split routing
sudo ./setup_split_routing.sh
```

### GitHub медленный
```bash
# Проверить маршруты
ip route get 140.82.121.3
# Если идет через tun0 — ошибка в настройках
```

### SSH отключается
```bash
# Проверить table 100
ip rule show | grep "lookup 100"
ip route show table 100
```

---

## Резюме

**Проблема:**
- OpenRouter/OpenAI заблокированы в РФ
- CDN-сервисы часто меняют IP
- VPN трафик ограничен 4 ГБ/месяц
- Docker/PyPI расходуют трафик быстро

**Решение:** Split routing по IP-диапазонам через policy routing.

**Результат:**
- ✅ OpenAI/OpenRouter работают через VPN (только трафик LLM)
- ✅ GitHub/Docker/PyPI работают напрямую (быстро, без ограничений)
- ✅ SSH всегда доступен
- ✅ 4 ГБ VPN хватит только для общения с нейросетями
- ✅ Не требует обновления списков IP

**Автоматизация:** Два скрипта делают всё автоматически.

**Экономия:** Контейнеры и pip-установки не трогают VPN-трафик!

---

**Дата обновления:** 2025-12-29  
**Статус:** ✅ Рабочая конфигурация подтверждена