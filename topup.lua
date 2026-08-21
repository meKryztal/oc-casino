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

-- Показывает экран ожидания с ЖИВЫМ списком того, что PIM видит в инвентаре игрока
-- прямо сейчас (обновляется само, без нажатий) - фильтр по конкретному кошельку.
-- Возвращает "go" (нажали Внести), nil (нажали Назад / сессия закрыта).
local function waitAndListItems(ui, pim, wallet)
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "Положите предметы в свой инвентарь.", ui.COLOR.TEXT_LIGHT)
        ui.text(4, 5, "Список ниже обновляется сам - заберём всё это по кнопке \"Внести\":", ui.COLOR.TEXT_MUTED)

        local scanOk, items = exchange.scanPlayerItems(pim)
        local y = 7
        if not scanOk then
            ui.text(4, y, "Не удалось прочитать инвентарь: " .. tostring(items), ui.COLOR.BTN_BG_2)
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
                ui.text(4, y, "(подходящих предметов пока не найдено)", ui.COLOR.TEXT_MUTED)
            else
                for _, name in ipairs(order) do
                    ui.text(4, y, name .. "  x" .. matched[name], ui.COLOR.ACCENT_GOLD)
                    y = y + 1
                end
            end
        end

        local goBox = ui.button(4, ui.H - 6, 20, 3, "Внести", ui.COLOR.BTN_BG)
        local backBox = ui.button(4, ui.H - 3, 20, 2, "Отмена", ui.COLOR.BTN_BG_2)

        -- короткий таймаут ожидания касания - если игрок ничего не нажал, просто
        -- перерисуем экран со свежим списком (эмуляция "живого" обновления)
        local tx, ty = ui.waitTouch(2)
        if ui.session.left then return nil end
        if tx then
            if ui.hit(goBox, tx, ty) then return "go" end
            if ui.hit(backBox, tx, ty) then return nil end
        end
    end
end

-- ===================== ПОПОЛНЕНИЕ =====================
function topup.deposit(ui, net, bankAddr, pim, storage, nick)
    local wallet = chooseWallet(ui, "пополнение")
    if not wallet then return end

    local action = waitAndListItems(ui, pim, wallet)
    if action ~= "go" then return end

    local taken, total, err = exchange.depositWallet(pim, wallet)
    if err then
        ui.messageBox("Ошибка", {
            "Не удалось прочитать/забрать предметы из инвентаря:",
            tostring(err):sub(1, 44),
            "Ничего не списано. Попробуйте ещё раз или",
            "запустите probe.lua и проверьте методы pim.",
        }, 8)
        return
    end
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
        if name ~= "_lastPushError" then
            lines[#lines + 1] = name .. " x" .. cnt
        end
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
