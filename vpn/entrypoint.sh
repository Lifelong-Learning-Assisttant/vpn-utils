#!/bin/bash
set -e

# Нейтральный entrypoint - запускаем bash и держим контейнер запущенным
# tail -f /dev/null держит процесс живым в фоновом режиме
exec tail -f /dev/null &
exec /bin/bash
