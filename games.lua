-- games.lua
-- Две мини-игры: Слоты, Кости.
-- Адаптировано под монитор 160×50.
-- Новая цветовая схема: тёмно-синий/бирюзовый акцент вместо бурого.

local config  = require("config")
local unicode = require("unicode")
local sprites = require("sprites")

local ulen = unicode.len
local games = {}

math.randomseed(os.time())

local function settle(net, bankAddr, nick, wallet, bet, win)
    local ok, result = net.call(bankAddr, {
        action = "settle_bet", nick = nick, wallet = wallet, bet = bet, win = win,
    })
    return ok, result
end

local function centerIn(x, w, str)
    return x + math.max(0, math.floor((w - ulen(str)) / 2))
end

-- ===================== ЦВЕТА ИГР =====================
-- Новая палитра: холодный тёмно-бирюзовый акцент.
local CLR = {
    BET_LCD_BG   = 0x030810,    -- фон LCD-табло ставки
    BET_LCD_FG   = 0x00E5CC,    -- цвет цифр на табло (бирюза)
    REEL_BORDER  = 0x00A8C0,    -- рамка барабана / кости / монеты (активно)
    REEL_DIM     = 0x204050,    -- рамка при анимации (тусклый)
    REEL_BG      = 0x0C1828,    -- фон внутри барабана
    PIP_CLR      = 0xE0E8F0,    -- очки кости (спрайт из 1.lua)
    PIP_DIM      = 0x304050,    -- очки кости в анимации (тусклые)
    SYMBOL_DIM   = 0x304050,    -- символ в анимации
    BTN_SPIN     = 0x966010,    -- "Крутить"   - тёмное золото

    -- кнопки выбора (кости)
    BTN_LESS     = 0x1C5C9C,    -- "Меньше 7"  - синий
    BTN_EQUAL    = 0x7A4A00,    -- "Ровно 7"   - янтарный
    BTN_MORE     = 0x1C7C5C,    -- "Больше 7"  - зелёный

    -- нейтральные
    BTN_NEUTRAL  = 0x1A1840,
    BTN_BACK     = 0x3A1010,
    BTN_CUSTOM   = 0x182840,
}

-- ===================== ШАПКА ИГРЫ =====================
-- На 160 колонках вся строка умещается без обрезки.
local function drawHeader(ui, title, balance, walletLabel, currentBet)
    local W = ui.W or 160
    local line = string.format(
        " \u{2666} %s   \u{25B6} Баланс: %d %s   \u{25B6} Ставка: %d  (мин %d / макс %d) ",
        title, balance, walletLabel, currentBet, config.MIN_BET, config.MAX_BET
    )
    local gpu = ui.gpu
    gpu.setBackground(ui.COLOR.WINDOW_TITLE or 0x0E0C2A)
    gpu.setForeground(ui.COLOR.ACCENT_GOLD)
    gpu.fill(1, 3, W, 1, " ")
    gpu.set(math.max(1, math.floor((W - ulen(line)) / 2)), 3, line)
end

-- ===================== ПАНЕЛЬ СТАВОК =====================
-- Панель прижата к правому краю (последние ~36 колонок) и занимает строки H-7 .. H.
-- Кнопка "Назад" - слева внизу.
local function drawBetUI(ui, currentBet)
    local W = ui.W or 160
    local H = ui.H or 50

    -- LCD-табло
    local lcdX = W - 38
    local lcdY = H - 9
    local lcdW = 36
    ui.rect(lcdX, lcdY, lcdW, 2, CLR.BET_LCD_BG)
    local lcdStr = "\u{25B6} СТАВКА: " .. currentBet
    ui.text(centerIn(lcdX, lcdW, lcdStr), lcdY, lcdStr, CLR.BET_LCD_FG, CLR.BET_LCD_BG)

    -- "Своя сумма" - под LCD, над пресетами
    local bCustom = ui.button(W - 38, H - 7, 36, 3, "Своя сумма \u{270E}", CLR.BTN_CUSTOM)

    -- Пресеты
    local bw = 11
    local b1 = ui.button(W - 38,        H - 3, bw, 3, "  10",  CLR.BTN_NEUTRAL)
    local b2 = ui.button(W - 38 + bw + 1, H - 3, bw, 3, "  50",  CLR.BTN_NEUTRAL)
    local b3 = ui.button(W - 38 + (bw+1)*2, H - 3, 13, 3, "  100", CLR.BTN_NEUTRAL)

    -- Кнопка "Назад" слева внизу
    local bExit = ui.button(3, H - 3, 16, 3, "\u{2190} Назад", CLR.BTN_BACK)

    return { b1=b1, b2=b2, b3=b3, bCustom=bCustom, bExit=bExit }
end

local function handleBetClick(ui, tx, ty, btns, currentBet)
    if ui.hit(btns.b1, tx, ty) then return 10,  false end
    if ui.hit(btns.b2, tx, ty) then return 50,  false end
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
        ui.messageBox("Ошибка", { "Недостаточно средств для ставки!" }, 2)
        return false
    end
    if currentBet < config.MIN_BET or currentBet > config.MAX_BET then
        ui.messageBox("Ошибка", { "Ставка вне допустимых лимитов!" }, 2)
        return false
    end
    return true
end

local function showRoundResult(ui, win, lines)
    if win > 0 then
        ui.messageBox("Выигрыш!", lines, 3.5)
    else
        ui.messageBox("Результат", lines, 2.8)
    end
end

-- ===================== СЛОТЫ =====================
-- Символы - те же мега-спрайты, что и на заставке казино (sprites.lua),
-- каждому символу соответствует свой фирменный цвет.
local SLOT_SYMBOLS = sprites.MEGA_KEYS  -- { "7", "$", "W", "D", "B" }
local SLOT_COLOR    = {}
for i, key in ipairs(SLOT_SYMBOLS) do
    SLOT_COLOR[key] = sprites.MEGA_COLORS[i]
end
local SLOT_PAYOUT  = { [3] = 10, [2] = 2 }

-- На 160 колонках три барабана могут быть заметно шире.
-- Спрайт максимум 15×10 ("$"), барабан 38×14 даёт запас со всех сторон.
local REEL_W, REEL_H = 38, 14
local REEL_GAP = 3

local function reelLayout(ui)
    local W = ui.W or 160
    local totalW = REEL_W * 3 + REEL_GAP * 2
    local startX = math.floor((W - totalW) / 2)
    local startY = 13  -- шапка=3, легенда=5, кнопка=7-10, отступ=11-12, барабаны с 13
    return startX, startY
end

local function drawReel(ui, x, y, symbol, borderColor, dim)
    local gpu = ui.gpu
    local bg = CLR.REEL_BG
    gpu.setBackground(bg)
    gpu.fill(x, y, REEL_W, REEL_H, " ")
    ui.drawBorder(x, y, REEL_W, REEL_H, borderColor, bg)

    -- мега-спрайт символа по центру барабана (15×10 максимум, барабан 38×14 - есть запас)
    local sw = sprites.megaWidth(symbol)
    local sx = x + math.max(0, math.floor((REEL_W - sw) / 2))
    local sy = y + math.max(0, math.floor((REEL_H - sprites.MEGA_H) / 2))
    local color = dim and CLR.SYMBOL_DIM or (SLOT_COLOR[symbol] or CLR.REEL_BORDER)
    sprites.drawMega(gpu, symbol, sx, sy, color, bg)
end

local function drawReels(ui, symbols, spinning)
    local startX, startY = reelLayout(ui)
    for i = 1, 3 do
        local x = startX + (i - 1) * (REEL_W + REEL_GAP)
        drawReel(ui, x, startY, symbols[i],
            spinning and CLR.REEL_DIM or CLR.REEL_BORDER, spinning)
    end
    return startX, startY
end

function games.slots(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet  = math.max(config.MIN_BET, math.min(10, balance))
    local idleSymbols = { SLOT_SYMBOLS[1], SLOT_SYMBOLS[2], SLOT_SYMBOLS[3] }

    local spinBtn, betBtns
    local function redraw()
        ui.clear(ui.COLOR.DESKTOP_BG)
        drawHeader(ui, "СЛОТЫ", balance, walletLabel, currentBet)

        -- Легенда комбинаций — строка 5, под шапкой (строка 3) с отступом
        local legend = "3 одинаковых = x" .. SLOT_PAYOUT[3] ..
                       "          2 одинаковых = x" .. SLOT_PAYOUT[2]
        ui.centerText(5, legend, ui.COLOR.TEXT_MUTED)

        -- Кнопка "Крутить" - строки 7-10 (высота 4)
        local spinW  = 50
        local spinX  = math.floor(((ui.W or 160) - spinW) / 2)
        spinBtn = ui.button(spinX, 7, spinW, 4, "\u{1F3B0}  КРУТИТЬ  \u{1F3B0}", CLR.BTN_SPIN)

        drawReels(ui, idleSymbols, false)
        betBtns = drawBetUI(ui, currentBet)
    end

    local needsRedraw = true
    while true do
        if needsRedraw then redraw(); needsRedraw = false end

        local tx, ty = ui.waitTouch(60)
        if not tx then return end

        local exitClicked
        local prevBet = currentBet
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end
        if currentBet ~= prevBet then needsRedraw = true end

        if ui.hit(spinBtn, tx, ty) then
            if validateBet(ui, currentBet, balance) then
                -- Анимация вращения
                for _ = 1, 20 do
                    drawReels(ui, {
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    }, true)
                    os.sleep(0.07)
                end

                local reels = {
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                }
                drawReels(ui, reels, false)
                idleSymbols = reels

                local counts  = {}
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
                    showRoundResult(ui, win, {
                        
                        "Комбинация! Выигрыш: +" .. win,
                        "Баланс: " .. balance
                    })
                else
                    showRoundResult(ui, 0, {
                        
                        "Не повезло в этот раз.",
                        "Баланс: " .. balance
                    })
                end
                needsRedraw = true
            end
        end
    end
end

-- ===================== КОСТИ =====================
local DICE_PIPS = {
    [1] = { {2,2} },
    [2] = { {1,1}, {3,3} },
    [3] = { {1,1}, {2,2}, {3,3} },
    [4] = { {1,1}, {1,3}, {3,1}, {3,3} },
    [5] = { {1,1}, {1,3}, {2,2}, {3,1}, {3,3} },
    [6] = { {1,1}, {2,1}, {3,1}, {1,3}, {2,3}, {3,3} },
}

-- Очки теперь рисуются спрайтом sprites.PIP (13×8, взят из 1.lua) вместо "●●".
-- Сетка 3×3 таких спрайтов (padding=1, colGap=2, rowGap=1) задаёт минимальный
-- размер кости: ширина = 3*13 + 2*2 + 2*1 = 45, высота = 3*8 + 2*1 + 2*1 = 28.
local DIE_PADDING = 1
local DIE_COL_GAP = 2
local DIE_ROW_GAP = 1
local DIE_W = sprites.PIP_W * 3 + DIE_COL_GAP * 2 + DIE_PADDING * 2  -- 45
local DIE_H = sprites.PIP_H * 3 + DIE_ROW_GAP * 2 + DIE_PADDING * 2  -- 28
local DIE_GAP = 10

local function diceLayout(ui)
    local W = ui.W or 160
    local H = ui.H or 50
    local totalW = DIE_W * 2 + DIE_GAP
    local startX = math.floor((W - totalW) / 2)
    -- Свободное место по вертикали: после кнопок выбора (строки 5-8) и до
    -- панели ставок (начинается на H-9). Кости центрируем в этом промежутке -
    -- при DIE_H=28 это чуть ниже кнопок, с равными отступами сверху и снизу.
    local availTop    = 9
    local availBottom = H - 10
    local avail       = availBottom - availTop + 1
    local startY = availTop + math.max(0, math.floor((avail - DIE_H) / 2))
    return startX, startY
end

local function drawDie(ui, x, y, value, borderColor, dim)
    local gpu = ui.gpu
    local bg = CLR.REEL_BG
    gpu.setBackground(bg)
    gpu.fill(x, y, DIE_W, DIE_H, " ")
    ui.drawBorder(x, y, DIE_W, DIE_H, borderColor, bg)

    local pips = DICE_PIPS[value] or {}
    local originX = x + DIE_PADDING
    local originY = y + DIE_PADDING
    local pipColor = dim and CLR.PIP_DIM or CLR.PIP_CLR

    for _, p in ipairs(pips) do
        local px = originX + (p[2] - 1) * (sprites.PIP_W + DIE_COL_GAP)
        local py = originY + (p[1] - 1) * (sprites.PIP_H + DIE_ROW_GAP)
        sprites.drawPip(gpu, px, py, pipColor, bg)
    end
end

local function drawDicePair(ui, d1, d2, borderColor, dim)
    local sx, sy = diceLayout(ui)
    drawDie(ui, sx,               sy, d1, borderColor, dim)
    drawDie(ui, sx + DIE_W + DIE_GAP, sy, d2, borderColor, dim)
end

function games.dice(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    local lastD1, lastD2 = 3, 4

    local lessBox, eqBox, moreBox, betBtns
    local function redraw()
        ui.clear(ui.COLOR.DESKTOP_BG)
        drawHeader(ui, "КОСТИ", balance, walletLabel, currentBet)

        -- Кнопки выбора - широкие, чётко разнесены по экрану
        local W = ui.W or 160
        local bw = 42
        local gap = 3
        local totalBW = bw * 3 + gap * 2
        local bx0 = math.floor((W - totalBW) / 2)

        lessBox = ui.button(bx0,              5, bw, 4, "  \u{25C4} МЕНЬШЕ 7  (x2)", CLR.BTN_LESS)
        eqBox   = ui.button(bx0 + bw + gap,   5, bw, 4, "  \u{25C6} РОВНО 7  (x5)",  CLR.BTN_EQUAL)
        moreBox = ui.button(bx0 + (bw+gap)*2, 5, bw, 4, "  БОЛЬШЕ 7  (x2) \u{25BA}", CLR.BTN_MORE)

        drawDicePair(ui, lastD1, lastD2, CLR.REEL_BORDER)
        betBtns = drawBetUI(ui, currentBet)
    end

    local needsRedraw = true
    while true do
        if needsRedraw then redraw(); needsRedraw = false end

        local tx, ty = ui.waitTouch(60)
        if not tx then return end

        local exitClicked
        local prevBet = currentBet
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end
        if currentBet ~= prevBet then needsRedraw = true end

        local choice
        if ui.hit(lessBox, tx, ty) then choice = "less"  end
        if ui.hit(eqBox,   tx, ty) then choice = "equal" end
        if ui.hit(moreBox, tx, ty) then choice = "more"  end

        if choice then
            if validateBet(ui, currentBet, balance) then
                for _ = 1, 18 do
                    drawDicePair(ui, math.random(1, 6), math.random(1, 6), CLR.REEL_DIM, true)
                    os.sleep(0.07)
                end

                local d1, d2 = math.random(1, 6), math.random(1, 6)
                local sum    = d1 + d2
                drawDicePair(ui, d1, d2, CLR.REEL_BORDER)
                lastD1, lastD2 = d1, d2

                local win = 0
                if choice == "less"  and sum < 7 then win = currentBet * 2 end
                if choice == "more"  and sum > 7 then win = currentBet * 2 end
                if choice == "equal" and sum == 7 then win = currentBet * 5 end

                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then return end

                balance = result.balance
                local sumLine = string.format("Кубики: %d + %d = %d", d1, d2, sum)
                if win > 0 then
                    showRoundResult(ui, win, { sumLine, "Выигрыш: +" .. win, "Баланс: " .. balance })
                else
                    showRoundResult(ui, 0,   { sumLine, "Не повезло в этот раз.", "Баланс: " .. balance })
                end
                needsRedraw = true
            end
        end
    end
end

return games
