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

-- Считывает всё, что лежит в инвентаре игрока (через pim).
-- Возвращает ok(boolean), items_или_сообщение_об_ошибке.
-- ok=true  -> второй результат - список { slot=, name=, count=, cfg= } только для распознанных предметов.
-- ok=false -> второй результат - текст ошибки (например, если у pim нет метода getAllStacks
--             или он требует других аргументов - это и роняло сессию раньше).
function exchange.scanPlayerItems(pim)
    if not pim.getAllStacks then
        return false, "у pim нет метода getAllStacks (проверьте probe.lua)"
    end

    local callOk, stacksOrErr = pcall(pim.getAllStacks, 0)
    if not callOk then
        return false, tostring(stacksOrErr)
    end

    local found = {}

    -- В разных сборках OpenComputers/AE2-мостов getAllStacks(side) возвращает
    -- ЛИБО функцию-итератор (для generic for), ЛИБО обычную таблицу-список стаков.
    -- Раньше код всегда делал "for stack in stacksOrErr do", что падало с
    -- "attempt to call a table value", если вернулась таблица. Обрабатываем оба случая.
    local function addStack(slotIndex, stack)
        if stack and stack.name and stack.size and stack.size > 0 then
            local cfg = findResourceConfig(stack.name)
            if cfg then
                found[#found + 1] = { slot = slotIndex, name = stack.name, count = stack.size, cfg = cfg }
            end
        end
    end

    if type(stacksOrErr) == "function" then
        -- вариант "итератор"
        local slot = 0
        for stack in stacksOrErr do
            addStack(slot, stack)
            slot = slot + 1
        end
    elseif type(stacksOrErr) == "table" then
        -- вариант "таблица" - ключи это номера слотов (могут начинаться с 0 или с 1)
        for slotIndex, stack in pairs(stacksOrErr) do
            addStack(tonumber(slotIndex) or 0, stack)
        end
    else
        return false, "getAllStacks вернул неожиданный тип: " .. type(stacksOrErr)
    end

    return true, found
end

-- Забирает у игрока ВСЕ распознанные предметы одного кошелька (chips или credits) и
-- проталкивает их в хранилище.
-- Возвращает: taken (списанные предметы {itemName=count,...} или nil при ошибке),
--             total (сумма в валюте кошелька),
--             err (текст ошибки, если что-то пошло не так, иначе nil).
function exchange.depositWallet(pim, wallet)
    local scanOk, items = exchange.scanPlayerItems(pim)
    if not scanOk then
        return nil, 0, items
    end

    local total = 0
    local taken = {}
    for _, it in ipairs(items) do
        local isCredits = (it.cfg == config.SERVER_CURRENCY)
        local matches = (wallet == "credits" and isCredits) or (wallet == "chips" and not isCredits)
        if matches then
            local callOk, pushed = pcall(pim.pushItem, exchange.STORAGE_SIDE, it.slot, it.count)
            if callOk and pushed then
                total = total + it.count * it.cfg.rate
                taken[it.name] = (taken[it.name] or 0) + it.count
            elseif not callOk then
                -- не роняем всю операцию из-за одного стака - просто пропускаем его,
                -- но запомним причину на случай, если вообще ничего не заберётся
                taken._lastPushError = tostring(pushed)
            end
        end
    end
    return taken, total, nil
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
