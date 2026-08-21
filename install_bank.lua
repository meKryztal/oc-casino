-- install_bank.lua
-- Установщик БАНК-СЕРВЕРА. Скачивает актуальные файлы из вашего GitHub-репозитория
-- и настраивает автозапуск. Запускать на компьютере с Internet Card + Network Card
-- (экран и PIM не обязательны).
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

local INSTALL_DIR = "/home/casino/"
local FILES = { "config.lua", "netlib.lua", "bank_server.lua" }

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

print("=== Установка казино (банк-сервер) ===")
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

writeFile(INSTALL_DIR .. "run_bank.lua", [[
-- run_bank.lua (сгенерирован установщиком)
-- Крутит банк-сервер в бесконечном цикле с автоперезапуском.
while true do
    local ok, err = pcall(dofile, "/home/casino/bank_server.lua")
    if not ok then
        print("[casino] Ошибка, перезапуск через 2 сек: " .. tostring(err))
        os.sleep(2)
    end
end
]])
print("  + " .. INSTALL_DIR .. "run_bank.lua")

local shrcLine = "/home/casino/run_bank.lua"
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

print("")
print("Готово! Перезагрузка через 5 секунд...")
os.sleep(5)
computer.shutdown(true)
