local config = require("config")
local sides = require("sides")

local exchange = {}

-- Сторона, в которую PIM выталкивает предметы при ПРИЁМЕ (adapter/pim -> хранилище).
exchange.STORAGE_SIDE = sides.up

-- Сторона, с которой ME-интерфейс кладёт предметы при ВЫДАЧЕ игроку.
-- Подтверждено перебором (probe_give_side.lua): у вас это north.
exchange.GIVE_SIDE = sides.north

-- Включает/выключает запись диагностического лога в exchange_debug.txt.
-- Поставьте false, когда всё заработает стабильно, чтобы не плодить лишний файл.
exchange.DEBUG = false

local function debugLog(msg)
    if not exchange.DEBUG then return end
    local f = io.open("exchange_debug.txt", "a")
    if f then
        f:write(string.format("[%s] %s\n", os.date(), msg))
        f:close()
    end
end

local function findResourceConfig(itemName)
    for _, r in ipairs(config.RESOURCES) do
        if r.itemName == itemName then return r end
    end
    if itemName == config.SERVER_CURRENCY.itemName then
        return config.SERVER_CURRENCY
    end
    return nil
end



-- Превращает результат depositWallet ({itemName=count,...}) в список строк
-- с человекочитаемыми метками вместо technical id.
-- Возвращает массив строк вида "Железный слиток x5".
function exchange.formatTaken(taken)
    local lines = {}
    for itemName, count in pairs(taken) do
        if itemName ~= "_lastPushError" then
            local cfg = findResourceConfig(itemName)
            local label = (cfg and cfg.label) or itemName
            lines[#lines + 1] = string.format("%s x%d", label, count)
        end
    end
    return lines
end


-- Считывает всё, что лежит в инвентаре игрока (через pim).
-- Возвращает ok(boolean), items_или_сообщение_об_ошибке.
-- ok=true  -> второй результат - список { slot=, name=, count=, cfg= } только для распознанных предметов.
-- ok=false -> второй результат - текст ошибки.
function exchange.scanPlayerItems(pim)
    if not pim.getAllStacks then
        return false, "у pim нет метода getAllStacks (проверьте probe.lua)"
    end

    local callOk, stacksOrErr = pcall(pim.getAllStacks, 0)
    if not callOk then
        return false, tostring(stacksOrErr)
    end

    local found = {}

    -- getAllStacks(side) может вернуть ЛИБО функцию-итератор, ЛИБО таблицу-список стаков.
    local function addStack(slotIndex, stack)
        if not stack then return end
        -- Поддерживаем оба варианта именования полей: id/qty и name/size.
        local itemId = stack.id or stack.name
        local qty = stack.qty or stack.size
        if itemId and qty and qty > 0 then
            local cfg = findResourceConfig(itemId)
            if cfg then
                found[#found + 1] = { slot = slotIndex, name = itemId, count = qty, cfg = cfg }
            end
        end
    end

    if type(stacksOrErr) == "function" then
        local slot = 0
        for stack in stacksOrErr do
            addStack(slot, stack)
            slot = slot + 1
        end
    elseif type(stacksOrErr) == "table" then
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
                taken._lastPushError = tostring(pushed)
            end
        end
    end
    return taken, total, nil
end

-- ============ ВЫДАЧА ИГРОКУ (вывод / выигрыш) ============

-- Выдаёт игроку amount предметов itemName через ME-интерфейс.
-- Делает несколько попыток по частям (например, если max_size стека меньше amount,
-- или если инвентарь игрока временно не принимает часть предметов).
-- Возвращает: ok(boolean), реально_выдано(number)
local function giveItemToPlayer(pim, storage, itemName, amount)
    debugLog(string.format("giveItemToPlayer: item=%s amount=%d side=%s",
        itemName, amount, tostring(exchange.GIVE_SIDE)))

    if storage.exportItem then
        local totalGiven = 0
        local maxAttempts = 50 -- защита от зависания, если предмет никак не удаётся выдать
        local attempts = 0

        while totalGiven < amount and attempts < maxAttempts do
            attempts = attempts + 1
            local remaining = amount - totalGiven

            local ok, res = pcall(storage.exportItem, { id = itemName, dmg = 0 }, exchange.GIVE_SIDE, remaining)

            debugLog(string.format("exportItem attempt=%d ok=%s res=%s", attempts, tostring(ok),
                (ok and type(res) == "table") and ("size=" .. tostring(res.size)) or tostring(res)))

            if ok and type(res) == "table" and res.size and res.size > 0 then
                totalGiven = totalGiven + res.size
            else
                -- Не удалось переместить в этой попытке (например, инвентарь игрока заполнился) - выходим.
                break
            end
        end

        return totalGiven > 0, totalGiven
    end

    -- Запасной вариант, если у storage нет exportItem, но у pim есть симметричный pullItem.
    if pim.pullItem then
        local ok, moved = pcall(pim.pullItem, exchange.GIVE_SIDE, 1, amount)
        debugLog(string.format("pim.pullItem ok=%s moved=%s", tostring(ok), tostring(moved)))
        if ok and moved and moved > 0 then
            return true, moved
        end
        return false, 0
    end

    debugLog("giveItemToPlayer: нет ни exportItem, ни pullItem")
    return false, 0
end

-- Пытается выдать игроку предметы на сумму walletAmount кошелька wallet (по конфигу ресурсов).
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

    local ok, givenCount = giveItemToPlayer(pim, storage, cfg.itemName, itemCount)
    return ok, givenCount or 0
end

return exchange
