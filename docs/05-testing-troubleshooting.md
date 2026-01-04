# Тестирование и troubleshooting

## 1. Проверить IP Kilo CLI (из dev):

```bash
docker exec -it dev curl --silent https://api.ipify.org
```

Ожидаемый результат: IP провайдера VPN.

---

## 2. Проверить IP вызова, инициированного extension (если есть опция теста в расширении)

* Если расширение имеет diagnostic/log или кнопку «test connection», запустите её и посмотрите исходящий IP на стороне LLM-провайдера, либо просмотрите логи/headers.

---

## 3. Принудительный тест из VS Code Server процесса

* Внутри dev выполните: `curl --proxy http://127.0.0.1:1090 https://api.ipify.org` — проверяет, что http-proxy дает egress через VPN.

---

## 4. Если extension всё ещё делает прямые вызовы

* проверьте настройку расширения (есть ли параметр backend/local cli);
* включите env `HTTP_PROXY`/`HTTPS_PROXY` для процесса code-server (в dev-compose) и перезапустите code-server;
* при необходимости, запустить локальный sidecar (например `socat`) внутри dev, который форвардит внешние вызовы в proxy внутри vpn.

---

## Обновлённый checklist перед production

* [ ] Создать сеть `vpn-net` заранее (скрипт/Makefile).
* [ ] В `compose` всех apps указать `external: true` для `vpn-net`.
* [ ] Решить поведение приложений при отсутствии proxy (ждать/фейлить/фолбэк).
* [ ] Решить порядок запуска: предпочтительно сначала `vpn`, потом `dev/apps`.
* [ ] Не забыть про безопасность: если используется fallback на прямой доступ — понимать риски утечки credentials/LLM-запросов.
* [ ] Kilo CLI внутри dev делает запросы через tun0 (проверено);
* [ ] VS Code extension Kilo Code использует локальный Kilo backend / CLI или уважает `http.proxy` (проверено);
* [ ] Если extension делает прямые вызовы — настроить extension или запустить его backend внутри dev;
* [ ] Никаких proxy-портов не проброшено на хост;
* [ ] Логи proxy не содержат Authorization header;
* [ ] Настроен мониторинг и alerting для VPN/proxy.
