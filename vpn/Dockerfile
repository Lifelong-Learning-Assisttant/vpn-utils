FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl iproute2 iputils-ping procps \
    dnsmasq tinyproxy dante-server sudo \
 && rm -rf /var/lib/apt/lists/*

# Установка adguardvpn-cli вручную (скачивание архива напрямую)
RUN mkdir -p /opt/adguardvpn_cli \
 && curl -fsSL https://github.com/AdguardTeam/AdGuardVPNCLI/releases/download/v1.6.24-release/adguardvpn-cli-1.6.24-linux-x86_64.tar.gz \
    -o /tmp/adguardvpn-cli.tar.gz \
 && tar -xzf /tmp/adguardvpn-cli.tar.gz -C /opt/adguardvpn_cli --strip-components=1 \
 && ln -sf /opt/adguardvpn_cli/adguardvpn-cli /usr/local/bin/adguardvpn-cli \
 && rm /tmp/adguardvpn-cli.tar.gz

# Конфиги и скрипты
COPY danted.conf /etc/danted.conf
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY start-vpn.sh /usr/local/bin/start-vpn.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start-vpn.sh

EXPOSE 1080 1090

# Не пробрасываем порты наружу на хост — они нужны для связи внутри docker-сети
CMD ["/usr/local/bin/entrypoint.sh"]
