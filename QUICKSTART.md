# Казино на OpenComputers — быстрый старт (GitHub → установка → настройка)

## Шаг 1. Залить проект на GitHub

1. Зайдите на [github.com](https://github.com) → **New repository** → назовите, например `oc-casino` → **Public** (обязательно, иначе `raw.githubusercontent.com` не отдаст файлы) → Create.
2. У себя на ПК, в папке со всеми `.lua`-файлами и `config.lua`:
   ```
   git init
   git add .
   git commit -m "casino init"
   git branch -M main
   git remote add origin https://github.com/USERNAME/REPO.git
   git push -u origin main
   ```
   (Замените `USERNAME/REPO` на свои.) Если нет `git` — на странице репозитория есть кнопка **Add file → Upload files**, можно просто перетащить все `.lua` мышкой.
3. Ссылка на сырые файлы, которую будут использовать установщики:
   ```
   https://raw.githubusercontent.com/USERNAME/REPO/main/<имя_файла>
   ```

## Шаг 2. Подставить свою ссылку в установщики

Откройте на GitHub (или локально) `install_bank.lua` и `install_station.lua`, в самом начале файла поправьте строку:

```lua
local RAW_BASE = "https://raw.githubusercontent.com/USERNAME/REPO/main"
```

на свою (`USERNAME/REPO` → ваш логин и имя репозитория). Закоммитьте/загрузите изменение обратно на GitHub.

## Шаг 3. Установка банк-сервера (1 компьютер в стойке)

На компьютере с **Internet Card + Network Card** (экран не обязателен):

```
wget https://raw.githubusercontent.com/USERNAME/REPO/main/install_bank.lua install_bank.lua
install_bank.lua
```

Установщик скачает `config.lua`, `netlib.lua`, `bank_server.lua`, пропишет автозапуск и перезагрузит компьютер — банк тихо поднимется в фоне и будет слушать сеть.

## Шаг 4. Установка каждой станции (повторить на всех 2+ компьютерах)

На компьютере с **Internet Card + Network Card + PIM + монитор (GPU той же серии)**:

```
wget https://raw.githubusercontent.com/USERNAME/REPO/main/install_station.lua install_station.lua
install_station.lua
```

После перезагрузки на экране сразу появится кастомный рабочий стол "К А З И Н О" — обычного OpenOS-шелла игрок не увидит никогда.

## Шаг 5. Обязательная проверка перед реальной игрой

На **каждой станции** один раз выполните:

```
/home/casino/probe.lua
```

и посмотрите `/home/probe_result.txt` — если у вас не `me_interface`, а другой компонент хранилища (например `transposer`), впишите его название в `/home/casino/main.lua` (переменная `STORAGE_COMPONENT`). Если метод выдачи предметов в `exchange.lua` (`storage.exportItem`) не подходит под вашу сборку модов — пришлите мне список методов из `probe_result.txt`, подставлю точный вызов.

## Шаг 6. Настройка под ваш сервер

Откройте `/home/casino/config.lua` **одинаково на банке и всех станциях**:

- `config.RESOURCES` — какие предметы принимает касса и курс обмена на фишки (`itemName`, `label`, `rate`).
- `config.SERVER_CURRENCY.itemName` — предмет-валюта вашего сервера.
- `config.MIN_BET` / `config.MAX_BET` — лимиты ставок.

На каждой станции в `/home/casino/exchange.lua`:

- `exchange.STORAGE_SIDE` — сторона света, в которую PIM подключён к хранилищу (`sides.up`, `sides.north` и т.д.).

После правки конфигов на GitHub — просто переустановите (`install_bank.lua` / `install_station.lua`) на нужных компьютерах, они всегда тянут актуальную версию файлов из репозитория.

## Обновление в будущем

Изменили что-то в репозитории на GitHub → на компьютере снова:
```
wget -f https://raw.githubusercontent.com/USERNAME/REPO/main/install_station.lua install_station.lua
install_station.lua
```
(`-f` — перезаписать локальный install-файл, если он уже есть). Ничего вручную копировать не нужно.

## Если `wget` недоступен на голом OpenOS

Установите Internet Card в компьютер и в BIOS/настройках мода OpenComputers разрешите доступ к `raw.githubusercontent.com` (если у вас на сервере включён вайтлист хостов для Internet Card — добавьте туда `raw.githubusercontent.com`).
