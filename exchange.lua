-- exchange.lua
-- Физический обмен предметами между игроком (через PIM) и хранилищем станции (ME-интерфейс).
--
-- !!! ВАЖНО, ПРОЧТИТЕ ПЕРЕД ЗАПУСКОМ !!!
-- Приём предметов у игрока (pim.pushItem) я взял из вашего рабочего примера - это надёжно.
-- А вот ОБРАТНАЯ операция - выдать игроку предметы (выигрыш/вывод) - в разных версиях
-- AE2-мостов для OpenComputers называется по-разному (exportItem, pushItem с другим направлением,
-- send и т.д.). Чтобы не гадать и не сломать вам инвентарь, сначала запустите probe.lua
-- (идёт в комплекте) - он выведет точный список методов вашего me_interface/transposer.
-- Пришлите мне этот список - я подставлю верный вызов в функцию giveItemToPlayer() ниже.
-- Сейчас там стоит рабочий вариант "по умолчанию" для типового ME Interface моста,
-- но его нужно подтвердить на вашей сборке модов.

local config = require("config")
local sides = require("sides")

local exchange = {}

-- Сторона, в которую PIM выталкивает/принимает предметы (адаптер -> интерфейс хранилища).
-- Подставьте вашу сторону (sides.up, sides.down, sides.north и т.д.) по обустройству блока.
exchange.STORAGE_SIDE = sides.up

local function findResourceConfig(itemName)
    for _, r in ipairs(config.RESOURCES) do
        if r.itemName == itemName then return r end
    end
    if itemName == config.SERVER_CURRENCY.itemName then
        return config.SERVER_CURRENCY
    end
    return nil
end

-- Считывает всё, что лежит в инвентаре игрока (через pim), и возвращает
-- список { slot=, name=, count=, resourceCfg= } только для распознанных предметов.
function exchange.scanPlayerItems(pim)
    local found = {}
    local stacks = pim.getAllStacks(0)
    local slot = 0
    for stack in stacks do
        slot = slot + 1
        if stack and stack.name and stack.size and stack.size > 0 then
            local cfg = findResourceConfig(stack.name)
            if cfg then
                found[#found + 1] = { slot = slot - 1, name = stack.name, count = stack.size, cfg = cfg }
            end
        end
    end
    return found
end

-- Забирает у игрока ВСЕ распознанные предметы одного кошелька (chips или credits) и
-- проталкивает их в хранилище. Возвращает: списанные предметы {itemName=count,...} и сумму в валюте кошелька.
function exchange.depositWallet(pim, wallet)
    local items = exchange.scanPlayerItems(pim)
    local total = 0
    local taken = {}
    for _, it in ipairs(items) do
        local isCredits = (it.cfg == config.SERVER_CURRENCY)
        local matches = (wallet == "credits" and isCredits) or (wallet == "chips" and not isCredits)
        if matches then
            local ok = pim.pushItem(exchange.STORAGE_SIDE, it.slot, it.count)
            if ok then
                total = total + it.count * it.cfg.rate
                taken[it.name] = (taken[it.name] or 0) + it.count
            end
        end
    end
    return taken, total
end

-- ============ ВЫДАЧА ИГРОКУ (вывод / выигрыш) ============
-- storage - обёртка над компонентом хранилища (me_interface / transposer), см. station/main.lua,
-- где он передаётся как component.me_interface (или другое имя - уточним после probe.lua).

local function giveItemToPlayer(pim, storage, itemName, amount)
    -- ВАРИАНТ ПО УМОЛЧАНИЮ: типовой ME Interface бридж умеет exportItem(filter, side, amount)
    -- и кладёт предметы в блок, к которому подключён интерфейс (в нашем случае - к pim через adapter).
    -- Если у вашего компонента метод называется иначе - замените строку ниже.
    if storage.exportItem then
        local ok, moved = pcall(storage.exportItem, { name = itemName }, exchange.STORAGE_SIDE, amount)
        return ok and moved and moved > 0
    end

    -- ЗАПАСНОЙ ВАРИАНТ: если у pim есть метод приёма предметов (симметричный pushItem), пробуем его.
    if pim.pullItem then
        local ok, moved = pcall(pim.pullItem, exchange.STORAGE_SIDE, 1, amount)
        return ok and moved and moved > 0
    end

    return false
end

-- Пытается выдать игроку предметы на сумму amount кошелька wallet (по конфигу ресурсов).
-- resourceItemName - какой именно ресурс выбрал игрок для вывода (для chips) или nil (для credits).
-- Возвращает: ok(boolean), actuallyGivenCount(number)
function exchange.withdrawToPlayer(pim, storage, wallet, resourceItemName, walletAmount)
    local cfg
    if wallet == "credits" then
        cfg = config.SERVER_CURRENCY
    else
        for _, r in ipairs(config.RESOURCES) do
            if r.itemName == resourceItemName then cfg = r break end
        end
    end
    if not cfg then return false, 0 end

    local itemCount = math.floor(walletAmount / cfg.rate)
    if itemCount <= 0 then return false, 0 end

    local ok = giveItemToPlayer(pim, storage, cfg.itemName, itemCount)
    return ok, ok and itemCount or 0
end

return exchange
