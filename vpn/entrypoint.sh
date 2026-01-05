#!/bin/bash
set -e

# Нейтральный entrypoint - держим контейнер запущенным
# tail -f /dev/null держит процесс живым
exec tail -f /dev/null
