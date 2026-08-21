-- games.lua
-- Три мини-игры. Каждая: спрашивает ставку -> считает результат -> одним RPC-вызовом
-- settle_bet атомарно списывает ставку и начисляет выигрыш на банк-сервере -> показывает итог.

local config = require("config")

local games = {}

math.randomseed(os.time())

local function askBet(ui, walletLabel, balance)
    if balance < config.MIN_BET then
        ui.messageBox("Недостаточно средств", {
            "На кошельке \"" .. walletLabel .. "\" меньше минимальной ставки.",
            "Пополните счёт через кассу.",
        }, 4)
        return nil
    end
    local bet = ui.numpad("Ставка (" .. walletLabel .. ")", 5)
    if not bet then return nil end
    if bet < config.MIN_BET or bet > config.MAX_BET then
        ui.messageBox("Некорректная ставка", {
            string.format("Ставка должна быть от %d до %d.", config.MIN_BET, config.MAX_BET),
        }, 3)
        return nil
    end
    if bet > balance then
        ui.messageBox("Недостаточно средств", { "На кошельке не хватает средств для такой ставки." }, 3)
        return nil
    end
    return bet
end

local function settle(net, bankAddr, nick, wallet, bet, win)
    local ok, result = net.call(bankAddr, {
        action = "settle_bet", nick = nick, wallet = wallet, bet = bet, win = win,
    })
    return ok, result
end

-- ===================== СЛОТЫ =====================
local SLOT_SYMBOLS = { "\u{1F352}", "\u{1F34B}", "\u{1F514}", "\u{2B50}", "7\u{20E3}" }
local SLOT_PAYOUT = { [3] = 10, [2] = 2 } -- 3 одинаковых = x10, 2 одинаковых = x2

function games.slots(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local bet = askBet(ui, walletLabel, balance)
    if not bet then return end

    local reels = { SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)] }
    local counts = {}
    for _, s in ipairs(reels) do counts[s] = (counts[s] or 0) + 1 end
    local maxCount = 0
    for _, c in pairs(counts) do if c > maxCount then maxCount = c end end

    local win = 0
    if SLOT_PAYOUT[maxCount] then
        win = bet * SLOT_PAYOUT[maxCount]
    end

    local ok, result = settle(net, bankAddr, nick, wallet, bet, win)
    if not ok then
        ui.messageBox("Ошибка", { "Не удалось провести ставку: " .. tostring(result) }, 4)
        return
    end

    local resultLine = table.concat(reels, "  |  ")
    if win > 0 then
        ui.messageBox("СЛОТЫ - Выигрыш!", {
            resultLine, "", string.format("Выигрыш: +%d (%s)", win, walletLabel),
            "Баланс: " .. tostring(result.balance),
        }, 6)
    else
        ui.messageBox("СЛОТЫ", {
            resultLine, "", "Увы, не повезло.",
            "Баланс: " .. tostring(result.balance),
        }, 5)
    end
end

-- ===================== КОСТИ (больше/меньше 7 на 2д6) =====================
function games.dice(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local bet = askBet(ui, walletLabel, balance)
    if not bet then return end

    -- сначала спрашиваем прогноз
    local choice
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "Кости: сумма двух кубиков против 7", ui.COLOR.TEXT_LIGHT)
        local lessBox = ui.button(4, 8, 20, 3, "Меньше 7", ui.COLOR.BTN_BG)
        local moreBox = ui.button(28, 8, 20, 3, "Больше 7", ui.COLOR.BTN_BG)
        local eqBox   = ui.button(52, 8, 20, 3, "Ровно 7 (x5)", ui.COLOR.BTN_BG_2)
        local tx, ty = ui.waitTouch(30)
        if not tx then return end
        if ui.hit(lessBox, tx, ty) then choice = "less" break end
        if ui.hit(moreBox, tx, ty) then choice = "more" break end
        if ui.hit(eqBox, tx, ty) then choice = "equal" break end
    end

    local d1, d2 = math.random(1, 6), math.random(1, 6)
    local sum = d1 + d2
    local win = 0
    if choice == "less" and sum < 7 then win = bet * 2 end
    if choice == "more" and sum > 7 then win = bet * 2 end
    if choice == "equal" and sum == 7 then win = bet * 5 end

    local ok, result = settle(net, bankAddr, nick, wallet, bet, win)
    if not ok then
        ui.messageBox("Ошибка", { "Не удалось провести ставку: " .. tostring(result) }, 4)
        return
    end

    ui.messageBox("КОСТИ", {
        string.format("Выпало: %d + %d = %d", d1, d2, sum),
        win > 0 and ("Выигрыш: +" .. win) or "Увы, не повезло.",
        "Баланс: " .. tostring(result.balance),
    }, 6)
end

-- ===================== МОНЕТКА =====================
function games.coinflip(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local bet = askBet(ui, walletLabel, balance)
    if not bet then return end

    local choice
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "Монетка: орёл или решка (x2)", ui.COLOR.TEXT_LIGHT)
        local headsBox = ui.button(4, 8, 20, 3, "Орёл", ui.COLOR.BTN_BG)
        local tailsBox = ui.button(28, 8, 20, 3, "Решка", ui.COLOR.BTN_BG)
        local tx, ty = ui.waitTouch(30)
        if not tx then return end
        if ui.hit(headsBox, tx, ty) then choice = "heads" break end
        if ui.hit(tailsBox, tx, ty) then choice = "tails" break end
    end

    local outcome = (math.random(1, 2) == 1) and "heads" or "tails"
    local win = (choice == outcome) and (bet * 2) or 0

    local ok, result = settle(net, bankAddr, nick, wallet, bet, win)
    if not ok then
        ui.messageBox("Ошибка", { "Не удалось провести ставку: " .. tostring(result) }, 4)
        return
    end

    ui.messageBox("МОНЕТКА", {
        "Выпало: " .. (outcome == "heads" and "Орёл" or "Решка"),
        win > 0 and ("Выигрыш: +" .. win) or "Увы, не повезло.",
        "Баланс: " .. tostring(result.balance),
    }, 5)
end

return games
