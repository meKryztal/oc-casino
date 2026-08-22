-- install_station.lua
-- Установщик СТАНЦИИ. Скачивает актуальные файлы из вашего GitHub-репозитория
-- и настраивает автозапуск (кастомный рабочий стол вместо шелла OpenOS).
-- Запускать на компьютере с Internet Card + Network Card + PIM + монитор/GPU.
--
-- ПЕРЕД ЗАГРУЗКОЙ НА GITHUB ОБЯЗАТЕЛЬНО ПОПРАВЬТЕ СТРОКУ НИЖЕ:
local RAW_BASE = "https://raw.githubusercontent.com/meKryztal/oc-casino/main"

local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

if not component.isAvailable("internet") then
    error("Не найдена Internet Card! Установите её и повторите попытку.")
end
local internet = require("internet")

-- ВРЕМЕННО ВЫКЛЮЧЕНО: пока идёт отладка/правки файлов, автозапуск casino
-- при загрузке компьютера не прописывается - после ошибки вас не будет
-- сразу выкидывать обратно в игру, и можно спокойно редактировать файлы
-- в обычном шелле OpenOS. Когда всё будет обкатано, поставьте true и
-- переустановите (или один раз выполните команду ниже вручную на станции:
--   echo "/home/casino/run.lua" >> /home/.shrc
local ENABLE_AUTOSTART = false

local INSTALL_DIR = "/home/casino/"
local FILES = {
    "config.lua", "netlib.lua", "ui.lua", "exchange.lua",
    "games.lua", "topup.lua", "main.lua",
    "screensaver.lua", "sprites.lua", -- нужны main.lua (заставка) и games.lua (спрайты)
}

local function download(url)
    local handle, err = internet.request(url)
    if not handle then error("Не удалось подключиться: " .. tostring(err)) end
    local data = {}
    for chunk in handle do data[#data + 1] = chunk end
    return table.concat(data)
end

local function writeFile(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not filesystem.exists(dir) then
        filesystem.makeDirectory(dir)
    end
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
end

print("=== Установка казино (станция) ===")
print("Источник: " .. RAW_BASE)

for _, name in ipairs(FILES) do
    local url = RAW_BASE .. "/" .. name
    print("Скачиваю " .. name .. " ...")
    local content = download(url)
    if not content or #content < 5 then
        error("Пустой или битый файл: " .. name .. " (проверьте RAW_BASE и что репозиторий публичный)")
    end
    writeFile(INSTALL_DIR .. name, content)
    print("  + " .. INSTALL_DIR .. name)
end

writeFile(INSTALL_DIR .. "run.lua", [[
-- run.lua (сгенерирован установщиком)
-- Крутит основной скрипт в бесконечном цикле с автоперезапуском.
-- Если main.lua упадёт (в т.ч. по Ctrl+Alt+C), просто перезапускается,
-- игрок никогда не увидит обычную командную строку OpenOS.
package.path = "/home/casino/?.lua;" .. package.path
while true do
    local ok, err = pcall(dofile, "/home/casino/main.lua")
    if not ok then
        print("[casino] Ошибка, перезапуск через 2 сек: " .. tostring(err))
        os.sleep(2)
    end
end
]])
print("  + " .. INSTALL_DIR .. "run.lua")

if ENABLE_AUTOSTART then
    local shrcLine = "/home/casino/run.lua"
    local shrcPath = "/home/.shrc"
    local existing = ""
    local rf = io.open(shrcPath, "r")
    if rf then existing = rf:read("*a") or "" rf:close() end
    if not existing:find(shrcLine, 1, true) then
        local wf = assert(io.open(shrcPath, "a"))
        wf:write("\n" .. shrcLine .. "\n")
        wf:close()
    end
    print("  + автозапуск прописан в /home/.shrc")
else
    print("  ! Автозапуск временно отключён (ENABLE_AUTOSTART = false в install_station.lua)")
    print("    Casino не стартует само при загрузке. Запускайте вручную командой:")
    print("      /home/casino/run.lua")
end

print("")
print("ВАЖНО: перед игрой запустите один раз /home/casino/probe.lua")
print("и пришлите содержимое /home/probe_result.txt, если вывод/выигрыши")
print("не будут выдаваться физически (см. exchange.lua).")

print("")
print("Готово! Перезагрузка через 5 секунд...")
os.sleep(5)
computer.shutdown(true)
