-- games.lua
-- Три мини-игры с непрерывным циклом, анимациями и пресетами ставок.

local config = require("config")

local games = {}

math.randomseed(os.time())

local function settle(net, bankAddr, nick, wallet, bet, win)
    local ok, result = net.call(bankAddr, {
        action = "settle_bet", nick = nick, wallet = wallet, bet = bet, win = win,
    })
    return ok, result
end

-- Вспомогательная функция для отрисовки панели ставок (внизу справа)
local function drawBetUI(ui, currentBet)
    local w = ui.W or 80
    local h = ui.H or 25
    
    ui.text(w - 28, h - 6, "Текущая ставка: " .. currentBet, ui.COLOR.TEXT_LIGHT)
    
    local b1 = ui.button(w - 28, h - 4, 7, 3, "10", ui.COLOR.BTN_BG)
    local b2 = ui.button(w - 20, h - 4, 7, 3, "50", ui.COLOR.BTN_BG)
    local b3 = ui.button(w - 12, h - 4, 8, 3, "100", ui.COLOR.BTN_BG)
    local bCustom = ui.button(w - 28, h - 8, 24, 3, "Своя сумма", ui.COLOR.BTN_BG)
    
    -- Кнопка выхода (слева внизу)
    local bExit = ui.button(4, h - 4, 12, 3, "Назад", ui.COLOR.BTN_BG)
    
    return {b1=b1, b2=b2, b3=b3, bCustom=bCustom, bExit=bExit}
end

-- Обработка нажатий на панель ставок
local function handleBetClick(ui, tx, ty, btns, currentBet)
    if ui.hit(btns.b1, tx, ty) then return 10, false end
    if ui.hit(btns.b2, tx, ty) then return 50, false end
    if ui.hit(btns.b3, tx, ty) then return 100, false end
    if ui.hit(btns.bCustom, tx, ty) then
        local b = ui.numpad("Своя ставка", 15)
        if b and b >= config.MIN_BET and b <= config.MAX_BET then 
            return b, false 
        end
    end
    if ui.hit(btns.bExit, tx, ty) then return currentBet, true end
    return currentBet, false
end

local function validateBet(ui, currentBet, balance)
    if currentBet > balance then
        ui.messageBox("Ошибка", {"Недостаточно средств для ставки!"}, 2)
        return false
    end
    if currentBet < config.MIN_BET or currentBet > config.MAX_BET then
        ui.messageBox("Ошибка", {"Ставка вне лимитов!"}, 2)
        return false
    end
    return true
end

-- ===================== СЛОТЫ =====================
local SLOT_SYMBOLS = { "\u{1F352}", "\u{1F34B}", "\u{1F514}", "\u{2B50}", "7\u{20E3}" }
local SLOT_PAYOUT = { [3] = 10, [2] = 2 }

function games.slots(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "СЛОТЫ | Баланс: " .. balance .. " " .. walletLabel, ui.COLOR.TEXT_LIGHT)
        
        local spinBtn = ui.button(30, 8, 20, 5, "КРУТИТЬ", ui.COLOR.BTN_BG_2)
        local betBtns = drawBetUI(ui, currentBet)
        
        local tx, ty = ui.waitTouch(60)
        if not tx then return end -- таймаут неактивности
        
        local exitClicked
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end
        
        if ui.hit(spinBtn, tx, ty) then
            if validateBet(ui, currentBet, balance) then
                -- Анимация прокрутки
                for i = 1, 10 do
                    local r = { SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)] }
                    ui.text(33, 15, table.concat(r, "  |  "), ui.COLOR.TEXT_MUTED)
                    os.sleep(0.08)
                end
                
                local reels = { SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)], SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)] }
                ui.text(33, 15, table.concat(reels, "  |  "), ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                
                local counts = {}
                for _, s in ipairs(reels) do counts[s] = (counts[s] or 0) + 1 end
                local maxCount = 0
                for _, c in pairs(counts) do if c > maxCount then maxCount = c end end
                
                local win = 0
                if SLOT_PAYOUT[maxCount] then win = currentBet * SLOT_PAYOUT[maxCount] end
                
                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then
                    ui.messageBox("Ошибка", { "Не удалось провести ставку!" }, 2)
                    return
                end
                
                balance = result.balance
                if win > 0 then
                    ui.text(35, 17, "Выигрыш: +" .. win, ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                    os.sleep(1.5)
                else
                    os.sleep(0.8)
                end
            end
        end
    end
end

-- ===================== КОСТИ =====================
function games.dice(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "КОСТИ | Баланс: " .. balance .. " " .. walletLabel, ui.COLOR.TEXT_LIGHT)
        
        local lessBox = ui.button(4, 8, 20, 5, "Меньше 7 (x2)", ui.COLOR.BTN_BG)
        local eqBox   = ui.button(28, 8, 20, 5, "Ровно 7 (x5)", ui.COLOR.BTN_BG_2)
        local moreBox = ui.button(52, 8, 20, 5, "Больше 7 (x2)", ui.COLOR.BTN_BG)
        
        local betBtns = drawBetUI(ui, currentBet)
        
        local tx, ty = ui.waitTouch(60)
        if not tx then return end
        
        local exitClicked
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end
        
        local choice
        if ui.hit(lessBox, tx, ty) then choice = "less" end
        if ui.hit(moreBox, tx, ty) then choice = "more" end
        if ui.hit(eqBox, tx, ty) then choice = "equal" end
        
        if choice then
            if validateBet(ui, currentBet, balance) then
                -- Анимация броска
                for i = 1, 8 do
                    ui.text(35, 15, "Кубики: " .. math.random(1,6) .. " и " .. math.random(1,6), ui.COLOR.TEXT_MUTED)
                    os.sleep(0.1)
                end
                
                local d1, d2 = math.random(1, 6), math.random(1, 6)
                local sum = d1 + d2
                ui.text(35, 15, "Кубики: " .. d1 .. " и " .. d2 .. " (Сумма: " .. sum .. ")", ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                
                local win = 0
                if choice == "less" and sum < 7 then win = currentBet * 2 end
                if choice == "more" and sum > 7 then win = currentBet * 2 end
                if choice == "equal" and sum == 7 then win = currentBet * 5 end
                
                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then return end
                
                balance = result.balance
                if win > 0 then
                    ui.text(35, 17, "Выигрыш: +" .. win, ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                    os.sleep(1.5)
                else
                    os.sleep(1)
                end
            end
        end
    end
end

-- ===================== МОНЕТКА =====================
function games.coinflip(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    
    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.text(4, 4, "МОНЕТКА | Баланс: " .. balance .. " " .. walletLabel, ui.COLOR.TEXT_LIGHT)
        
        local headsBox = ui.button(15, 8, 20, 5, "Орёл (x2)", ui.COLOR.BTN_BG)
        local tailsBox = ui.button(45, 8, 20, 5, "Решка (x2)", ui.COLOR.BTN_BG)
        
        local betBtns = drawBetUI(ui, currentBet)
        
        local tx, ty = ui.waitTouch(60)
        if not tx then return end
        
        local exitClicked
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end
        
        local choice
        if ui.hit(headsBox, tx, ty) then choice = "heads" end
        if ui.hit(tailsBox, tx, ty) then choice = "tails" end
        
        if choice then
            if validateBet(ui, currentBet, balance) then
                -- Анимация подкидывания
                local faces = {"Орёл", "Решка"}
                for i = 1, 8 do
                    ui.text(37, 15, "Летит... " .. faces[math.random(1,2)], ui.COLOR.TEXT_MUTED)
                    os.sleep(0.1)
                end
                
                local outcome = (math.random(1, 2) == 1) and "heads" or "tails"
                local outcomeText = outcome == "heads" and "Орёл" or "Решка"
                ui.text(37, 15, "Выпало: " .. outcomeText, ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                
                local win = (choice == outcome) and (currentBet * 2) or 0
                
                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then return end
                
                balance = result.balance
                if win > 0 then
                    ui.text(37, 17, "Выигрыш: +" .. win, ui.COLOR.ACCENT_GOLD or ui.COLOR.TEXT_LIGHT)
                    os.sleep(1.5)
                else
                    os.sleep(1)
                end
            end
        end
    end
end

return games
