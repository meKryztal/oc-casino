-- topup.lua
-- Экран "Касса": пополнение и вывод (Оптимизировано: центрирование, фикс подвала, снижение TPS)

local config = require("config")
local exchange = require("exchange")

local topup = {}

-- ===================== ЦЕНТРИРОВАННОЕ МЕНЮ =====================
local function chooseWallet(ui, titleSuffix)
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.centerText(4, "Касса - выберите кошелёк (" .. titleSuffix .. ")", ui.COLOR.TEXT_LIGHT)
        
        local bw = 30
        local cx = math.floor((ui.W - bw) / 2)
        
        local chipsBox = ui.button(cx, 8, bw, 4, config.WALLETS.chips.label, ui.COLOR.BTN_BG)
        local creditsBox = ui.button(cx, 13, bw, 4, config.WALLETS.credits.label, ui.COLOR.BTN_BG)
        
        -- Поднимаем подвал повыше (ui.H - 5), чтобы не обрезался рамкой монитора
        local backBox = ui.button(cx, ui.H - 5, bw, 3, "Назад", ui.COLOR.BTN_BG_2)
        
        local tx, ty = ui.waitTouch(60)
        if not tx then return nil end
        if ui.hit(chipsBox, tx, ty) then return "chips" end
        if ui.hit(creditsBox, tx, ty) then return "credits" end
        if ui.hit(backBox, tx, ty) then return nil end
    end
end

-- ===================== ЭКРАН ПОПОЛНЕНИЯ (БЕЗ СПАМА) =====================
local function waitAndListItems(ui, pim, wallet)
    -- Оптимизация: сканируем инвентарь ОДИН раз при открытии, а не по кругу
    local scanOk, items = exchange.scanPlayerItems(pim)
    
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.centerText(4, "Положите предметы в свой инвентарь.", ui.COLOR.TEXT_LIGHT)
        ui.centerText(5, "Список сформирован. Нажмите 'Внести' или 'Обновить'.", ui.COLOR.TEXT_MUTED)

        local y = 7
        if not scanOk then
            ui.centerText(y, "Не удалось прочитать инвентарь: " .. tostring(items), ui.COLOR.BTN_BG_2)
        else
            local matched = {}
            local order = {}
            for _, it in ipairs(items) do
                local isCredits = (it.cfg == config.SERVER_CURRENCY)
                local inThisWallet = (wallet == "credits" and isCredits) or (wallet == "chips" and not isCredits)
                if inThisWallet then
                    if not matched[it.name] then order[#order + 1] = it.name end
                    matched[it.name] = (matched[it.name] or 0) + it.count
                end
            end
            if #order == 0 then
                ui.centerText(y, "(подходящих предметов пока не найдено)", ui.COLOR.TEXT_MUTED)
            else
                for _, name in ipairs(order) do
                    ui.centerText(y, name .. "  x" .. matched[name], ui.COLOR.ACCENT_GOLD)
                    y = y + 1
                end
            end
        end

        -- Выстраиваем кнопки в центре и сильно выше нижнего края
        local bw_go = 20
        local bw_btn = 16
        local gap = 2
        local totalW = bw_go + gap + bw_btn + gap + bw_btn
        local startX = math.floor((ui.W - totalW) / 2)
        
        local goBox = ui.button(startX, ui.H - 5, bw_go, 3, "Внести", ui.COLOR.BTN_BG)
        local refreshBox = ui.button(startX + bw_go + gap, ui.H - 4, bw_btn, 2, "Обновить", ui.COLOR.BTN_BG_GOLD or 0xC9962C)
        local backBox = ui.button(startX + bw_go + gap + bw_btn + gap, ui.H - 4, bw_btn, 2, "Отмена", ui.COLOR.BTN_BG_2)

        -- Ожидаем касания долго, без спама проверками
        local tx, ty = ui.waitTouch(120)
        if ui.session.left then return nil end
        if tx then
            if ui.hit(goBox, tx, ty) then return "go" end
            if ui.hit(refreshBox, tx, ty) then 
                scanOk, items = exchange.scanPlayerItems(pim) -- ручное обновление
            end
            if ui.hit(backBox, tx, ty) then return nil end
        end
    end
end

-- ===================== ЛОГИКА ПОПОЛНЕНИЯ =====================
function topup.deposit(ui, net, bankAddr, pim, storage, nick)
    local wallet = chooseWallet(ui, "пополнение")
    if not wallet then return end

    local action = waitAndListItems(ui, pim, wallet)
    if action ~= "go" then return end

    local taken, total, err = exchange.depositWallet(pim, wallet)
    if err then
        ui.messageBox("Ошибка", {
            "Не удалось прочитать/забрать предметы:",
            tostring(err):sub(1, 44),
            "Запустите probe.lua и проверьте методы pim."
        }, 8)
        return
    end
    if total <= 0 then
        ui.messageBox("Касса", { "Не найдено подходящих предметов." }, 4)
        return
    end

    local ok, result = net.call(bankAddr, { action = "deposit", nick = nick, wallet = wallet, amount = total })
    if not ok then
        ui.messageBox("Ошибка", { "Банк не подтвердил зачисление: " .. tostring(result) }, 8)
        return
    end

    local lines = { "Зачислено: +" .. total .. " (" .. config.WALLETS[wallet].label .. ")" }
    for name, cnt in pairs(taken) do
        if name ~= "_lastPushError" then lines[#lines + 1] = name .. " x" .. cnt end
    end
    lines[#lines + 1] = "Новый баланс: " .. tostring(result.balance)
    ui.messageBox("Успешно", lines, 6)
end

-- ===================== ЛОГИКА ВЫВОДА =====================
function topup.withdraw(ui, net, bankAddr, pim, storage, nick, balances)
    local wallet = chooseWallet(ui, "вывод")
    if not wallet then return end

    local resourceItemName = nil
    if wallet == "chips" then
        while true do
            ui.clear(ui.COLOR.DESKTOP_BG)
            ui.centerText(4, "В каком ресурсе вывести фишки?", ui.COLOR.TEXT_LIGHT)
            local boxes = {}
            local bw = 40
            local cx = math.floor((ui.W - bw) / 2)
            
            for i, r in ipairs(config.RESOURCES) do
                local y = 7 + (i - 1) * 4
                local box = ui.button(cx, y, bw, 3, r.label .. " (курс " .. r.rate .. ")", ui.COLOR.BTN_BG)
                boxes[#boxes + 1] = { item = r.itemName, box = box }
            end
            
            local backBox = ui.button(cx, ui.H - 5, bw, 3, "Отмена", ui.COLOR.BTN_BG_2)
            
            local tx, ty = ui.waitTouch(60)
            if not tx then return end
            
            if ui.hit(backBox, tx, ty) then return end
            
            local chosen = nil
            for _, b in ipairs(boxes) do
                if ui.hit(b.box, tx, ty) then chosen = b.item break end
            end
            if chosen then resourceItemName = chosen break end
        end
    else
        resourceItemName = config.SERVER_CURRENCY.itemName
    end
    
    if not resourceItemName then return end

    local balance = balances[wallet] or 0
    local amount = ui.numpad("Сумма вывода", 6)
    if not amount then return end
    if amount > balance then
        ui.messageBox("Ошибка", { "Недостаточно средств." }, 3)
        return
    end

    local ok, result = net.call(bankAddr, { action = "withdraw", nick = nick, wallet = wallet, amount = amount })
    if not ok then
        ui.messageBox("Ошибка", { "Банк отклонил вывод." }, 4)
        return
    end

    local giveOk, given = exchange.withdrawToPlayer(pim, storage, wallet, resourceItemName, amount)
    if giveOk then
        ui.messageBox("Вывод", { "Выдано предметов: " .. given, "Остаток: " .. tostring(result.balance) }, 5)
    else
        local refundOk, refundResult = net.call(bankAddr, { action = "refund", nick = nick, wallet = wallet, amount = amount })
        if refundOk then
            ui.messageBox("Возврат", { "В хранилище пусто или недоступно.", "Средства возвращены: " .. tostring(refundResult.balance) }, 6)
        end
    end
end

return topup
