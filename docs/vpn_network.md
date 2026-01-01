# Архитектура: VPN + Host-Proxy для LLM-запросов

## Короткое описание / Цель архитектуры

Цель — гарантировать, что все вызовы LLM (OpenAI, Gemini, OpenRouter и т.д.) из вашей сети идут через VPN, но при этом:

* не трогать глобальные таблицы маршрутизации Docker-контейнеров/хоста
* не поддерживать списки IP провайдеров
* не маркировать пакеты ipset/fwmarkveth-ns
* минимально менять приложение: только те python-модули, которые делают LLM-вызовы, будут направлять трафик через прокси;
* Kilo (Node.js) запускается непосредственно в `vpn-ns` и всегда использует VPN;
* VS Code Server и Python-приложения направляют LLM-вызовы на локальные прокси (SOCKS5 и HTTP), которые живут в `vpn-ns` и делают egress через `tun0`.

Это учебный, простой и воспроизводимый подход: централизованные прокси + VPN namespace с разделением трафика.

## Архитектура сети

```mermaid
graph TB
    subgraph Host["Host Network"]
        veth_host["veth-host<br/>10.0.0.1"]
        
        subgraph HostAccess["HostAccess (socat)"]
            socat_socks["SOCKS5 Forward<br/>1080 → 10.0.0.2:1080"]
            socat_http["HTTP Forward<br/>1090 → 10.0.0.2:1090"]
        end
        
        subgraph Apps["Applications"]
            Python["Python/LLM<br/>socks5h://localhost:1080"]
            VSCode["VS Code Server<br/>http://localhost:1090"]
        end
    end
    
    subgraph VPN_NS["vpn-ns (Network Namespace)"]
        veth_ns["veth-ns<br/>10.0.0.2"]
        
        subgraph InternetAccess["Internet Access (veth)"]
            note_veth["Для установки VPN<br/>и прокси в namespace"]
        end
        
        subgraph VPN["VPN Layer"]
            tun0["tun0<br/>(AdGuard VPN)"]
            dns["DNS Resolver<br/>(AdGuard)"]
        end
        
        subgraph ProxyLayer["Proxy Layer"]
            Dante["Dante<br/>SOCKS5 :1080<br/>egress → tun0"]
            Tinyproxy["Tinyproxy<br/>HTTP :1090<br/>egress → tun0"]
        end
        
        Kilo["Kilo CLI<br/>Node.js<br/>внутри vpn-ns"]
    end
    
    Internet["Internet<br/>LLM Providers<br/>OpenAI, Gemini, etc."]
    
    %% Host to VPN-NS connections
    Python --> socat_socks
    VSCode --> socat_http
    
    socat_socks --> veth_ns
    socat_http --> veth_ns
    
    veth_host --> veth_ns
    
    %% VPN-NS internal connections
    veth_ns --> Dante
    veth_ns --> Tinyproxy
    
    Dante --> tun0
    Tinyproxy --> tun0
    Kilo --> tun0
    
    tun0 --> Internet
```

**Пояснение:**
* **veth-ns/veth-host** — создается для доступа namespace в интернет (установка VPN, прокси, пакетов)
* **socat** — пробрасывает порты 1080 и 1090 из host в namespace для работы приложений
* **Dante** — SOCKS5 прокси для Python/LLM приложений
* **Tinyproxy** — HTTP прокси для VS Code Server

## Компоненты и их роли

**vpn-ns (network namespace)** — отдельное сетевое пространство, внутри которого находятся:

* `tun0` — VPN-интерфейс, поднятый `adguardvpn-cli`.
* `adguardvpn-cli` — управляет соединением и DNS (resolver) внутри namespace.
* `Dante` — SOCKS5 прокси, слушает порт 1080, делает egress через `tun0`.
* `Tinyproxy` — HTTP прокси, слушает порт 1090, делает egress через `tun0`.
* `Kilo CLI` (Node.js) — запускается внутри `vpn-ns`, весь его трафик идёт через VPN автоматически.
* `veth-ns` — veth-интерфейс (10.0.0.2) для связи с host.

**Host namespace (host)**:

* docker bridge / контейнеры (App A/B) — запускаются в обычном сетевом пространстве и по умолчанию используют прямой интернет (eth0).
* VS Code Server — использует HTTP proxy (порт 1090) для LLM-вызовов и расширений.
* `HostAccess (SOCKS5)` — проброс порта 1080 → vpn-ns:1080 (Dante).
* `HostAccess (HTTP)` — проброс порта 1090 → vpn-ns:1090 (Tinyproxy).
* `veth-host` — veth-интерфейс (10.0.0.1) для связи с vpn-ns.

**Интернет / LLM провайдеры** — OpenAI, Gemini, OpenRouter и т.д. — все LLM-запросы проходят через VPN, когда они идут через прокси или когда их генерирует Kilo внутри `vpn-ns`.

**Разделение прокси:**
* **Порт 1080 (SOCKS5)**: Python-приложения, Kilo CLI, LLM-вызовы
* **Порт 1090 (HTTP)**: VS Code Server, расширения VS Code

---

## Почему так сделано (преимущества)

* **Минимальные изменения в приложениях**: менять нужно только те модули, которые делают LLM-вызовы — направлять их на локальный proxy. Остальной код остается без изменений.
* **Нет политики маркировки пакетов/сложного routing**: не нужно поддерживать ipset/синхронизацию CIDR-ов LLM провайдеров.
* **DNS под контролем**: `adguardvpn-cli` обеспечивает DNS внутри vpn-namespace, поэтому proxy резолвит имена через VPN (сокращая риск утечек).
* **Чёткая граница**: Kilo — в VPN (все его соединения защищены), другие сервисы — прицельно отправляют LLM-трафик через прокси.
* **Простота**: легко поднять, отлаживать и тестировать в учебном проекте.
* **Разделение прокси**: SOCKS5 (порт 1080) для Python/LLM и HTTP (порт 1090) для VS Code Server позволяет оптимизировать настройки под каждый тип приложения.

---

## Как компоненты общаются (примеры потоков)

### 1) Kilo (Node.js) делает LLM-запрос

* Kilo работает в `vpn-ns`.
* Запрос — через `tun0` → VPN провайдер → LLM.
* DNS для запроса — через `adguardvpn-cli` в `vpn-ns`.

### 2) Python-приложение (контейнер) делает LLM-вызов

* `App` создаёт LLM-сессию/transport, указывая прокси `socks5h://HOST:1080`.
* Внутренний трафик к прокси идёт через `HostAccess` (порт 1080 проброшен).
* Dante (SOCKS5), находясь в `vpn-ns`, резолвит хост и делает egress через `tun0`.
* Остальной трафик App (pip, git и т. п.) идёт напрямую через eth0.

### 3) VS Code Server и расширения

* VS Code Server настроен на HTTP proxy `http://HOST:1090`.
* Для HTTPS VS Code использует CONNECT → Tinyproxy делает резолв и выполняет egress через `tun0`.
* LLM-запросы от расширений идут через этот proxy.

---

## DNS: как предотвратить утечки

* `adguardvpn-cli` запускается в `vpn-ns` и поднимает DNS resolver в этом namespace. Proxy делает DNS-резолв через adguard.
* **SOCKS5 (Dante)**: используйте `socks5h://` — тогда DNS-резолв выполняется на стороне прокси внутри VPN.
* **HTTP (Tinyproxy)**: VS Code использует CONNECT — Tinyproxy резолвит DNS внутри VPN.
* **Kilo CLI**: работает внутри `vpn-ns`, DNS идет через adguardvpn-cli.

---

## Proxy: рекомендации по выбору и настройке

**Два прокси для разных задач:**

**SOCKS5 (Dante) — порт 1080:**
* **Тип**: SOCKS5 с поддержкой `socks5h` (ресолв у прокси).
* **Требования**:
  * Поддержка streaming / long-lived connections (для LLM streaming).
  * Не буферизировать ответы (чтобы streaming работал корректно).
  * Не делать MITM TLS.
* **Использование**: Python-приложения, Kilo CLI, LLM-вызовы.

**HTTP (Tinyproxy) — порт 1090:**
* **Тип**: HTTP proxy с поддержкой CONNECT.
* **Требования**:
  * Поддержка HTTPS через CONNECT.
  * Не буферизировать ответы.
  * Не делать MITM TLS.
* **Использование**: VS Code Server, расширения VS Code.

**HostAccess**: пробрасываете host:1080 → vpn-ns:1080 и host:1090 → vpn-ns:1090.

---

## HostAccess: варианты доступа из host → vpn-ns

**Текущая реализация — Port forwarding (проброс портов):**

1. **SOCKS5 (порт 1080)**: host:1080 → vpn-ns:1080 (Dante)
   * Простой способ в учебном окружении.
   * Python-приложения используют `socks5h://localhost:1080`.

2. **HTTP (порт 1090)**: host:1090 → vpn-ns:1090 (Tinyproxy)
   * VS Code Server использует `http://localhost:1090`.

**Важно:** veth-интерфейсы (`veth-host` и `veth-ns`) используются **только для первоначального доступа в интернет** внутри namespace (чтобы установить VPN и прокси). Проброс портов для приложений идет через `socat` отдельно.

**Альтернатива — veth pair + host-side IP:**
* Создать veth-пару (10.0.0.1/10.0.0.2), пробросить трафик.
* Более «чистый» сетевой вариант, чуть сложнее при настройке.

> Для быстрого запуска используется проброс портов через `socat`.

---

## Интеграция в код (минимальные шаблоны)

**VS Code Server** (settings.json)

```json
{
  "http.proxy": "http://localhost:1090",
  "http.proxyStrictSSL": true
}
```

**Python — пример `llm_client` (sync/async)**

`requests` (sync)

```python
import requests

def get_llm_session():
    s = requests.Session()
    s.proxies.update({
        "http": "socks5h://localhost:1080",
        "https": "socks5h://localhost:1080",
    })
    return s

def call_llm(payload):
    s = get_llm_session()
    r = s.post("https://api.openai.com/v1/...", json=payload, headers={"Authorization":"Bearer ..."})
    return r.json()
```

`httpx` (async)

```python
import httpx

async def call_llm_async(payload):
    async with httpx.AsyncClient(proxies="socks5h://localhost:1080") as client:
        r = await client.post("https://api.openai.com/v1/...", json=payload, headers={"Authorization":"Bearer ..."})
        return r.json()
```

**Примечание:**
* `localhost:1080` — SOCKS5 прокси (Dante) для Python/LLM
* `localhost:1090` — HTTP прокси (Tinyproxy) для VS Code
* Оба пробрасываются через `socat` из host в namespace

## Короткий чек-лист для запуска (без команд, только порядок действий)

1. Поднять `vpn-ns` и `adguardvpn-cli` → `tun0` + DNS (внутри vpn-ns).
2. Запустить `Dante` (SOCKS5, порт 1080) внутри `vpn-ns`.
3. Запустить `Tinyproxy` (HTTP, порт 1090) внутри `vpn-ns`.
4. Проверить, что оба прокси делают egress через `tun0`.
5. Организовать `HostAccess` через `socat`:
   - Проброс порта 1080 → vpn-ns:1080 (SOCKS5)
   - Проброс порта 1090 → vpn-ns:1090 (HTTP)
6. Запустить `Kilo` внутри `vpn-ns`.
7. Настроить VS Code Server: `http.proxy` → `http://localhost:1090`.
8. В Python-приложениях: использовать `socks5h://localhost:1080` для LLM-вызовов.
9. Включить health-check/alerting на proxy/VPN.
