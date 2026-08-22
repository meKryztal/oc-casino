-- topup.lua
-- Экран "Касса": пополнение и вывод.
-- Адаптировано под монитор 160×50.

local config   = require("config")
local exchange = require("exchange")

local topup = {}

-- ===================== ВЫБОР КОШЕЛЬКА =====================
local function chooseWallet(ui, titleSuffix)
    local W, H = ui.W or 160, ui.H or 50

    ui.clear(ui.COLOR.DESKTOP_BG)
    ui.centerText(6, "Касса \u{2014} " .. titleSuffix, ui.COLOR.ACCENT_GOLD)
    ui.centerText(8, "Выберите кошелёк:", ui.COLOR.TEXT_LIGHT)

    local bw = 48
    local cx = math.floor((W - bw) / 2)
    local midY = math.floor(H / 2)

    local chipsBox   = ui.button(cx, midY - 4, bw, 3, config.WALLETS.chips.label,   ui.COLOR.BTN_BG_GOLD)
    local creditsBox = ui.button(cx, midY + 1,  bw, 3, config.WALLETS.credits.label, 0x1E5C8C)
    local backBox    = ui.button(cx, H - 5,     bw, 3, "Назад",                      ui.COLOR.BTN_BG_2)

    while true do
        local tx, ty = ui.waitTouch(60)
        if not tx then return nil end
        if ui.hit(chipsBox,   tx, ty) then return "chips"   end
        if ui.hit(creditsBox, tx, ty) then return "credits" end
        if ui.hit(backBox,    tx, ty) then return nil       end
    end
end

-- ===================== ЭКРАН ПОПОЛНЕНИЯ =====================
local function waitAndListItems(ui, pim, wallet)
    local scanOk, items = exchange.scanPlayerItems(pim)

    local W, H = ui.W or 160, ui.H or 50
    local goBox, refreshBox, backBox

    local function redraw()
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.centerText(5, "Пополнение: положите предметы в инвентарь и нажмите «Внести».", ui.COLOR.TEXT_LIGHT)
        ui.centerText(7, "Список предметов:", ui.COLOR.TEXT_MUTED)

        local y = 9
        if not scanOk then
            ui.centerText(y, "Не удалось прочитать инвентарь: " .. tostring(items), ui.COLOR.BTN_BG_2)
        else
            local matched = {}
            local order   = {}
            local labels  = {}
            for _, it in ipairs(items) do
                local isCredits = (it.cfg == config.SERVER_CURRENCY)
                local inThisWallet = (wallet == "credits" and isCredits) or (wallet == "chips" and not isCredits)
                if inThisWallet then
                    if not matched[it.name] then
                        order[#order + 1]  = it.name
                        labels[it.name]    = (it.cfg and it.cfg.label) or it.name
                    end
                    matched[it.name] = (matched[it.name] or 0) + it.count
                end
            end
            if #order == 0 then
                ui.centerText(y, "(подходящих предметов пока не найдено)", ui.COLOR.TEXT_MUTED)
            else
                for _, name in ipairs(order) do
                    ui.centerText(y, labels[name] .. "  \u{00D7}  " .. matched[name], ui.COLOR.ACCENT_GOLD)
                    y = y + 1
                end
            end
        end

        -- Три кнопки в одну строку, центрированы, высота 3 (текст точно по центру)
        local bwGo  = 30
        local bwBtn = 22
        local gap   = 4
        local totalW = bwGo + gap + bwBtn + gap + bwBtn
        local sx    = math.floor((W - totalW) / 2)
        local btnY  = H - 5

        goBox      = ui.button(sx,                              btnY, bwGo,  3, "Внести",   ui.COLOR.BTN_BG_GOLD)
        refreshBox = ui.button(sx + bwGo + gap,                 btnY, bwBtn, 3, "Обновить", 0x1A2848)
        backBox    = ui.button(sx + bwGo + gap + bwBtn + gap,   btnY, bwBtn, 3, "Отмена",   ui.COLOR.BTN_BG_2)
    end

    local needsRedraw = true
    while true do
        if needsRedraw then
            redraw()
            needsRedraw = false
        end

        local tx, ty = ui.waitTouch(120)
        if ui.session.left then return nil end
        if not tx then
            -- Долгое ожидание - обновить список
            needsRedraw = true
        else
            if ui.hit(goBox,      tx, ty) then return "go" end
            if ui.hit(backBox,    tx, ty) then return nil  end
            if ui.hit(refreshBox, tx, ty) then
                scanOk, items = exchange.scanPlayerItems(pim)
                needsRedraw = true
            end
        end
    end
end

-- ===================== ЛОГИКА ПОПОЛНЕНИЯ =====================
function topup.deposit(ui, net, bankAddr, pim, storage, nick)
    local wallet = chooseWallet(ui, "Пополнение")
    if not wallet then return end

    local action = waitAndListItems(ui, pim, wallet)
    if action ~= "go" then return end

    local taken, total, err = exchange.depositWallet(pim, wallet)
    if err then
        ui.messageBox("Ошибка", {
            "Не удалось прочитать/забрать предметы:",
            tostring(err):sub(1, 60),
            "Проверьте методы pim через probe.lua.",
        }, 8)
        return
    end
    if total <= 0 then
        ui.messageBox("Касса", { "Не найдено подходящих предметов." }, 4)
        return
    end

    local ok, result = net.call(bankAddr, {
        action = "deposit", nick = nick, wallet = wallet, amount = total,
    })
    if not ok then
        ui.messageBox("Ошибка", { "Банк не подтвердил зачисление: " .. tostring(result) }, 8)
        return
    end

    local lines = { "Зачислено: +" .. total .. " (" .. config.WALLETS[wallet].label .. ")" }
    for _, line in ipairs(exchange.formatTaken(taken)) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = "Новый баланс: " .. tostring(result.balance)
    ui.messageBox("Успешно", lines, 6)
end

-- ===================== ЛОГИКА ВЫВОДА =====================
function topup.withdraw(ui, net, bankAddr, pim, storage, nick, balances)
    local W, H = ui.W or 160, ui.H or 50
    local wallet = chooseWallet(ui, "Вывод")
    if not wallet then return end

    local resourceItemName = nil
    if wallet == "chips" then
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.centerText(6, "В каком ресурсе вывести фишки?", ui.COLOR.TEXT_LIGHT)

        local bw  = 60
        local cx  = math.floor((W - bw) / 2)
        local boxes = {}

        for i, r in ipairs(config.RESOURCES) do
            local y   = 10 + (i - 1) * 5
            -- высота 3: текст ложится на строку y+1, ровно по центру
            local box = ui.button(cx, y, bw, 3,
                r.label .. "  (курс " .. r.rate .. " : 1)", 0x1A2848)
            boxes[#boxes + 1] = { item = r.itemName, box = box }
        end

        local backBox = ui.button(cx, H - 5, bw, 3, "Отмена", ui.COLOR.BTN_BG_2)

        while true do
            local tx, ty = ui.waitTouch(60)
            if not tx then return end
            if ui.hit(backBox, tx, ty) then return end
            for _, b in ipairs(boxes) do
                if ui.hit(b.box, tx, ty) then
                    resourceItemName = b.item
                    break
                end
            end
            if resourceItemName then break end
        end
    else
        resourceItemName = config.SERVER_CURRENCY.itemName
    end

    if not resourceItemName then return end

    local balance = balances[wallet] or 0
    local amount  = ui.numpad("Сумма вывода", 8)
    if not amount then return end
    if amount > balance then
        ui.messageBox("Ошибка", { "Недостаточно средств." }, 3)
        return
    end

    local ok, result = net.call(bankAddr, {
        action = "withdraw", nick = nick, wallet = wallet, amount = amount,
    })
    if not ok then
        ui.messageBox("Ошибка", { "Банк отклонил вывод: " .. tostring(result) }, 4)
        return
    end

    local giveOk, given = exchange.withdrawToPlayer(pim, storage, wallet, resourceItemName, amount)
    if giveOk then
        ui.messageBox("Вывод", {
            "Выдано предметов: " .. given,
            "Остаток: " .. tostring(result.balance),
        }, 5)
    else
        local refundOk, refundResult = net.call(bankAddr, {
            action = "refund", nick = nick, wallet = wallet, amount = amount,
        })
        if refundOk then
            ui.messageBox("Возврат", {
                "В хранилище пусто или недоступно.",
                "Средства возвращены: " .. tostring(refundResult.balance),
            }, 6)
        end
    end
end

return topup
