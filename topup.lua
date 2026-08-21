-- topup.lua
-- Экран "Касса": пополнение и вывод обоих кошельков.

local config = require("config")
local exchange = require("exchange")

local topup = {}

local function chooseWallet(ui, titleSuffix)
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "Касса - выберите кошелёк (" .. titleSuffix .. ")", ui.COLOR.TEXT_LIGHT)
        local chipsBox = ui.button(4, 8, 30, 3, config.WALLETS.chips.label, ui.COLOR.BTN_BG)
        local creditsBox = ui.button(4, 12, 30, 3, config.WALLETS.credits.label, ui.COLOR.BTN_BG)
        local backBox = ui.button(4, ui.H - 3, 30, 2, "Назад", ui.COLOR.BTN_BG_2)
        local tx, ty = ui.waitTouch(30)
        if not tx then return nil end
        if ui.hit(chipsBox, tx, ty) then return "chips" end
        if ui.hit(creditsBox, tx, ty) then return "credits" end
        if ui.hit(backBox, tx, ty) then return nil end
    end
end

-- ===================== ПОПОЛНЕНИЕ =====================
function topup.deposit(ui, net, bankAddr, pim, storage, nick)
    local wallet = chooseWallet(ui, "пополнение")
    if not wallet then return end

    ui.clear(ui.COLOR.DESKTOP_BG)
    ui.text(4, 4, "Положите предметы в свой инвентарь и коснитесь экрана,", ui.COLOR.TEXT_LIGHT)
    ui.text(4, 5, "когда всё готово (заберём всё подходящее сразу).", ui.COLOR.TEXT_LIGHT)
    local goBox = ui.button(4, 8, 20, 3, "Внести", ui.COLOR.BTN_BG)
    local backBox = ui.button(4, 12, 20, 2, "Отмена", ui.COLOR.BTN_BG_2)
    local tx, ty = ui.waitTouch(60)
    if not tx or not ui.hit(goBox, tx, ty) then
        if tx and ui.hit(backBox, tx, ty) then return end
        return
    end

    local taken, total = exchange.depositWallet(pim, wallet)
    if total <= 0 then
        ui.messageBox("Касса", { "Не найдено подходящих предметов у вас в инвентаре." }, 4)
        return
    end

    local ok, result = net.call(bankAddr, { action = "deposit", nick = nick, wallet = wallet, amount = total })
    if not ok then
        ui.messageBox("Ошибка", {
            "Предметы были списаны, но банк не подтвердил зачисление: " .. tostring(result),
            "Обратитесь к администратору, если баланс не обновился.",
        }, 8)
        return
    end

    local lines = { "Зачислено: +" .. total .. " (" .. config.WALLETS[wallet].label .. ")" }
    for name, cnt in pairs(taken) do
        lines[#lines + 1] = name .. " x" .. cnt
    end
    lines[#lines + 1] = "Новый баланс: " .. tostring(result.balance)
    ui.messageBox("Пополнение выполнено", lines, 6)
end

-- ===================== ВЫВОД =====================
function topup.withdraw(ui, net, bankAddr, pim, storage, nick, balances)
    local wallet = chooseWallet(ui, "вывод")
    if not wallet then return end

    local resourceItemName = nil
    if wallet == "chips" then
        -- дать выбрать, каким именно ресурсом хочет получить вывод
        while true do
            ui.clear(ui.COLOR.DESKTOP_BG)
            ui.text(4, 4, "В каком ресурсе вывести фишки?", ui.COLOR.TEXT_LIGHT)
            local boxes = {}
            for i, r in ipairs(config.RESOURCES) do
                local y = 6 + (i - 1) * 3
                local box = ui.button(4, y, 40, 2, r.label .. "  (курс " .. r.rate .. ")", ui.COLOR.BTN_BG)
                boxes[#boxes + 1] = { item = r.itemName, box = box }
            end
            local tx, ty = ui.waitTouch(30)
            if not tx then return end
            local chosen = nil
            for _, b in ipairs(boxes) do
                if ui.hit(b.box, tx, ty) then chosen = b.item break end
            end
            if chosen then resourceItemName = chosen break end
        end
    else
        resourceItemName = config.SERVER_CURRENCY.itemName
    end

    local balance = balances[wallet] or 0
    local amount = ui.numpad("Сумма вывода (" .. config.WALLETS[wallet].label .. ")", 6)
    if not amount then return end
    if amount > balance then
        ui.messageBox("Недостаточно средств", { "На кошельке нет такой суммы." }, 3)
        return
    end

    -- 1) резервируем средства на банке
    local ok, result = net.call(bankAddr, { action = "withdraw", nick = nick, wallet = wallet, amount = amount })
    if not ok then
        ui.messageBox("Ошибка", { "Банк отклонил вывод: " .. tostring(result) }, 4)
        return
    end

    -- 2) пытаемся физически выдать предметы
    local giveOk, given = exchange.withdrawToPlayer(pim, storage, wallet, resourceItemName, amount)
    if giveOk then
        ui.messageBox("Вывод выполнен", {
            "Выдано предметов: " .. given,
            "Остаток на балансе: " .. tostring(result.balance),
        }, 5)
    else
        -- 3) не получилось выдать физически - обязательно возвращаем деньги на баланс
        local refundOk, refundResult = net.call(bankAddr, { action = "refund", nick = nick, wallet = wallet, amount = amount })
        if refundOk then
            ui.messageBox("Не удалось выдать предметы", {
                "В хранилище не хватает предметов для выдачи.",
                "Средства возвращены на баланс: " .. tostring(refundResult.balance),
            }, 6)
        else
            ui.messageBox("КРИТИЧЕСКАЯ ОШИБКА", {
                "Не удалось ни выдать предметы, ни вернуть средства!",
                "Срочно сообщите администратору. Ник: " .. nick,
                "Кошелёк: " .. wallet .. ", сумма: " .. amount,
            }, 15)
        end
    end
end

return topup
