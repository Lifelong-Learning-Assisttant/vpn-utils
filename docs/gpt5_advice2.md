Мы Code server почему то не доступен по указанным им портам и адресам http://176.123.161.187:11650/ http://localhost:11650/

Диагностика:
sudo ip netns exec vpn-ns ss -tlnp | grep -E ':11650|code-server' || true LISTEN 0 511 0.0.0.0:11650 0.0.0.0:* users:(("node",pid=3115524,fd=22)) curl -v --connect-timeout 5 http://10.200.1.2:11650/ || echo "no-connect-to-10.200.1.2" * Trying 10.200.1.2:11650... * Connected to 10.200.1.2 (10.200.1.2) port 11650 (#0) > GET / HTTP/1.1 > Host: 10.200.1.2:11650 > User-Agent: curl/7.81.0 > Accept: */* > * Mark bundle as not supporting multiuse < HTTP/1.1 302 Found < Location: ./login < Vary: Accept, Accept-Encoding < Content-Type: text/plain; charset=utf-8 < Content-Length: 29 < Date: Tue, 06 Jan 2026 17:39:16 GMT < Connection: keep-alive < Keep-Alive: timeout=5 < * Connection #0 to host 10.200.1.2 left intact Found. Redirecting to ./login curl проходит а если я перейду по http://10.200.1.2:11650/ то ничего не открывается. sysctl net.ipv4.ip_forward net.ipv4.ip_forward = 1 sudo iptables -L FORWARD -n --line-numbers Chain FORWARD (policy DROP) num target prot opt source destination 1 CNI-FORWARD all -- 0.0.0.0/0 0.0.0.0/0 /* CNI firewall plugin rules */ 2 DOCKER-USER all -- 0.0.0.0/0 0.0.0.0/0 3 DOCKER-FORWARD all -- 0.0.0.0/0 0.0.0.0/0 4 ufw-before-logging-forward all -- 0.0.0.0/0 0.0.0.0/0 5 ufw-before-forward all -- 0.0.0.0/0 0.0.0.0/0 6 ufw-after-forward all -- 0.0.0.0/0 0.0.0.0/0 7 ufw-after-logging-forward all -- 0.0.0.0/0 0.0.0.0/0 8 ufw-reject-forward all -- 0.0.0.0/0 0.0.0.0/0 9 ufw-track-forward all -- 0.0.0.0/0 0.0.0.0/0 10 ACCEPT all -- 10.0.0.0/24 0.0.0.0/0 11 ACCEPT all -- 0.0.0.0/0 10.0.0.0/24 state RELATED,ESTABLISHED

Отлично — у нас всё ясно из выводов: сервис внутри namespace отвечает (10.200.1.2:11650 — возвращает редирект), IP-форвардинг включён, но FORWARD у тебя стоит в DROP и в правилах есть только разрешения для подсети 10.0.0.0/24, а не для нашей 10.200.1.0/24. Поэтому пакеты, которые приходят снаружи на HOST_IP:11650 и DNAT'ятся в 10.200.1.2:11650, уходят в FORWARD и там отбиваются.

Решение — добавить безопасные правила FORWARD, разрешающие трафик между хостом и подсетью veth, и правило для связанных соединений. Это не повлияет на SSH (мы не меняем политику INPUT) и безопасно делать в tmux.

Выполни (как root или через sudo) эти команды:

# 1) разрешить связанные/установленные соединения (conntrack)
sudo iptables -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# 2) разрешить форвард для подсети 10.200.1.0/24 (в обе стороны)
sudo iptables -I FORWARD 1 -s 10.200.1.0/24 -j ACCEPT
sudo iptables -I FORWARD 1 -d 10.200.1.0/24 -j ACCEPT


Пояснение:

-I FORWARD 1 вставляет правило в самое начало цепочки, чтобы оно сработало раньше, чем другие правила ufw/docker.

Первое правило позволяет ответным пакетам (RELATED,ESTABLISHED), вторые — новый трафик из/в нашу veth-подсеть.

После этого проверь (на сервере):

# 1) доступ с хоста к HOST_IP:11650 (тест локально, имитирует внешний коннект)
curl -v --connect-timeout 5 http://$(hostname -I | awk '{print $1}'):11650/ || echo "connect failed"

# 2) или curl с удалённого ПК: curl -v http://176.123.161.187:11650/


Ожидаем: HTTP/1.1 302 Found (редирект на /login) — значит всё работает, и браузер должен открыть страницу.

Если браузер снаружи всё ещё не видит порт:

Проверь, что фаервол на хосте (ufw) разрешает вход на порт 11650:

sudo ufw status numbered
sudo ufw allow 11650/tcp


Проверь, что провайдер/хостинг не блокирует порт и что адрес 176.123.161.187 действительно принадлежит этому серверу:

ip addr show | grep 176.123.161.187 -n || true


Если есть Docker/bridge политики — убедись, что правило DNAT в PREROUTING стоит (у тебя оно есть).

Про http://10.200.1.2:11650/ в браузере:

Ты писал, что curl http://10.200.1.2:11650/ возвращает редирект, но браузер «ничего не открывает». Если curl с сервера работает, но браузер с твоего ПК на адрес http://10.200.1.2:11650/ не доступен — это нормально: IP 10.200.1.2 — частный адрес в veth-сети и недоступен извне. Для доступа извне нужно использовать HOST_IP:11650 (DNAT) или проброс/сокеты на localhost (соцат).

Если ты в браузере на самом сервере пытаешься открыть http://10.200.1.2:11650/ — это должен делать локальный браузер на сервере (а их обычно нет). Для теста используй curl на сервере, как ты уже сделал.