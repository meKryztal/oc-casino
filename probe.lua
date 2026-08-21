-- probe.lua
-- ЗАПУСТИТЕ ЭТО ОДИН РАЗ на станции ПЕРЕД тем, как играть по-настоящему.
-- Выводит на экран и сохраняет в файл список методов у pim и у компонента хранилища
-- (me_interface / transposer / другое) - это нужно, чтобы я подставил в exchange.lua
-- правильный вызов для ВЫДАЧИ предметов игроку (приём уже сделан по вашему рабочему примеру).

local component = require("component")

local out = {}
local function log(s) print(s) out[#out + 1] = s end

log("=== Подключённые компоненты ===")
for address, ctype in component.list() do
    log(ctype .. "  ->  " .. address)
end

log("")
log("=== Методы pim (если есть) ===")
if component.isAvailable("pim") then
    local pim = component.pim
    for name in pairs(component.methods(pim.address)) do
        log("  pim." .. name)
    end
else
    log("  pim не найден на этом компьютере!")
end

log("")
log("=== Методы me_interface (если есть) ===")
if component.isAvailable("me_interface") then
    local me = component.me_interface
    for name in pairs(component.methods(me.address)) do
        log("  me_interface." .. name)
    end
else
    log("  me_interface не найден - проверьте, есть ли у вас transposer,")
    log("  storage_interface или другой компонент хранилища; впишите его имя")
    log("  в station/main.lua (переменная STORAGE_COMPONENT) и запустите probe.lua снова.")
end

local f = io.open("/home/probe_result.txt", "w")
if f then
    f:write(table.concat(out, "\n"))
    f:close()
    print("")
    print("Результат сохранён в /home/probe_result.txt")
end
