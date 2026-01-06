Коротко и по делу.

# Куда ставится

По умолчанию Remote-SSH ставит сервер в домашнюю папку пользователя, в каталог `~/.vscode-server` (для Insiders — `~/.vscode-server-insiders`). Там есть подкаталог `bin/<commit_hash>/`, внутри которого лежат исполняемые файлы и скрипт `server.sh`. Документация прямо указывает, что расширение устанавливает VS Code Server на удалённой машине, а в логах/issue'ах видно типичную структуру `~/.vscode-server/bin/<id>/server.sh`. ([code.visualstudio.com][1])

Есть также переменная окружения `VSCODE_AGENT_FOLDER`, которую расширение использует для указания папки агента (по умолчанию она указывает на `~/.vscode-server`). Если у вас какие-то кастомные настройки/скрипты — эта переменная может быть задействована. ([GitHub][2])

# Как вызвать (запустить) вручную

1. Посмотрите, какие версии/идентификаторы установлены:

```bash
ls -la ~/.vscode-server/bin/
```

2. Запустите `server.sh` из нужного каталога (замените `<commit>` на имя папки из предыдущей команды). Часто запускают с такими опциями (пример из логов/обсуждений):

```bash
~/.vscode-server/bin/<commit>/server.sh --port=0 --use-host-proxy --enable-remote-auto-shutdown
```

Можно перенаправить лог в файл и запустить в фоне:

```bash
~/.vscode-server/bin/<commit>/server.sh --port=0 --use-host-proxy --enable-remote-auto-shutdown \
  &> ~/.vscode-server/.server.<commit>.log &
```

Примеры похожих вызовов и логов можно найти в обсуждениях и репортах по Remote-SSH. ([Reddit][3])

# Полезные команды для отладки

* Смотреть логи установки/запуска:

```bash
tail -f ~/.vscode-server/*.log
```

* Найти запущенный процесс и убить его:

```bash
ps aux | grep server.sh
# или
pkill -f "/.vscode-server/bin/<commit>/server.sh"
```

(иногда в качестве быстрого способа — `pkill node`, но будьте осторожны, если на сервере работает другой node-процесс). ([GitHub][4])

# Ещё моменты

* Если сервер не устанавливается автоматически (нельзя скачать из интернета), часто вручную загружают архив и распаковывают в `~/.vscode-server/bin/<commit>/` — тогда `server.sh` там же. ([Medium][5])
* Для **VS Code Server / tunneling** (новые сценарии) есть CLI `code tunnel` / `code` — но это уже другой режим (tunnels). Обычный Remote-SSH использует `~/.vscode-server` и `server.sh`. ([code.visualstudio.com][6])

Если хочешь — могу подсказать конкретные команды под твою систему (покажешь вывод `ls ~/.vscode-server/bin` или `ps aux | grep vscode`), и помогу составить точную команду запуска/диагностики.

[1]: https://code.visualstudio.com/docs/remote/ssh "Remote Development using SSH"
[2]: https://github.com/microsoft/vscode-remote-release/issues/10026?utm_source=chatgpt.com "[Remote-SSH Bug]: VSCode failt to install code-server when i use ..."
[3]: https://www.reddit.com/r/vscode/comments/j3g7tq/segmentation_fault_and_vs_code_server_for_wsl/?utm_source=chatgpt.com "Segmentation Fault and VS Code Server for WSL closed unexpectedly"
[4]: https://github.com/microsoft/vscode-remote-release/issues/10403?utm_source=chatgpt.com "[Remote-SSH Bug]: `Kill Server` does not terminate the entire server ..."
[5]: https://medium.com/%40debugger24/installing-vscode-server-on-remote-machine-in-private-network-offline-installation-16e51847e275?utm_source=chatgpt.com "Installing VSCode Server on Remote Machine in Private Network ..."
[6]: https://code.visualstudio.com/docs/remote/vscode-server "Visual Studio Code Server"
