-- games.lua
-- Три мини-игры с непрерывным циклом, крупными анимациями и пресетами ставок.
--
-- ВАЖНО про "размер текста/эмодзи": экран станции - это ТЕКСТОВЫЙ режим
-- (сетка символов 80x25), а не растровая графика. У символа фиксированный
-- размер шрифта, задаваемый видеокартой/монитором - увеличить конкретную
-- букву/эмодзи через API нельзя. Поэтому "увеличение" реализовано через
-- укрупнение самих панелей-анимаций и декоративное обрамление символа
-- (доп. значки по бокам), чтобы он визуально был заметнее.

local config = require("config")
local unicode = require("unicode")

local ulen = unicode.len

local games = {}

math.randomseed(os.time())

local function settle(net, bankAddr, nick, wallet, bet, win)
    local ok, result = net.call(bankAddr, {
        action = "settle_bet", nick = nick, wallet = wallet, bet = bet, win = win,
    })
    return ok, result
end

-- Центрирует текст внутри блока шириной w, начинающегося с x (с учётом unicode-длины)
local function centerIn(x, w, str)
    return x + math.max(0, math.floor((w - ulen(str)) / 2))
end

-- ===================== ПАНЕЛЬ СТАВОК (низ экрана) =====================
-- Компактный, но хорошо видимый блок: LCD-строка с текущей ставкой, три
-- пресета, "своя сумма" и кнопка выхода. Цвета - нейтральные тёмно-сиреневые,
-- никакого зелёного/красного (это оставлено только для messageBox-ошибок).
--
-- Раскладка использует ВСЮ высоту экрана до самого низа (раньше 2 строки
-- внизу вообще не использовались), чтобы между "Своя сумма" и рядом
-- 10/50/100 появилась настоящая пустая строка-буфер, а не просто соседние
-- ряды пикселей, которые визуально выглядели слипшимися.
local function drawBetUI(ui, currentBet)
    local w = ui.W or 80
    local h = ui.H or 25

    -- LCD-табло текущей ставки
    local lcdW, lcdH = 24, 1
    local lcdX, lcdY = w - 28, h - 8
    ui.rect(lcdX, lcdY, lcdW, lcdH, 0x0A0A0A)
    local lcdStr = "\u{25B6} СТАВКА: " .. currentBet
    ui.text(centerIn(lcdX, lcdW, lcdStr), lcdY, lcdStr, 0x39FF6A, 0x0A0A0A)

    -- "Своя сумма" - буфер в 1 пустую строку и до LCD, и до пресетов ниже
    local bCustom = ui.button(w - 28, h - 6, 24, 3, "Своя сумма", ui.COLOR.BTN_BG_NEUTRAL)

    -- Пресеты ставки - прижаты к самому низу экрана, отделены пустой строкой
    -- от "Своя сумма" (раньше эти два ряда были вплотную и наезжали друг на друга)
    local b1 = ui.button(w - 28, h - 2, 7, 3, "10", ui.COLOR.BTN_BG_NEUTRAL)
    local b2 = ui.button(w - 20, h - 2, 7, 3, "50", ui.COLOR.BTN_BG_NEUTRAL)
    local b3 = ui.button(w - 12, h - 2, 8, 3, "100", ui.COLOR.BTN_BG_NEUTRAL)

    -- Кнопка выхода (слева внизу, на одном ряду с пресетами)
    local bExit = ui.button(4, h - 2, 12, 3, "Назад", ui.COLOR.BTN_BG_NEUTRAL)

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

-- Заголовок игры со ставкой - ставка теперь видна сразу в двух местах:
-- здесь (в шапке) и на LCD-табло рядом с пресетами. Здесь же указан лимит
-- максимальной ставки (берётся из config.MAX_BET, а не захардкожен), чтобы
-- игрок сразу видел потолок, не подбирая его через "Своя сумма".
local function drawHeader(ui, title, balance, walletLabel, currentBet)
    ui.text(4, 4, title .. "  |  Баланс: " .. balance .. " " .. walletLabel ..
        "  |  Ставка: " .. currentBet .. " (макс. " .. config.MAX_BET .. ")", ui.COLOR.TEXT_LIGHT)
end

-- Итог раунда показываем крупным модальным окном (как ошибки), а не мелкой
-- строкой посреди экрана - это заодно и "увеличивает" анимацию исхода.
local function showRoundResult(ui, win, lines)
    if win > 0 then
        ui.messageBox("Выигрыш!", lines, 3.5)
    else
        ui.messageBox("Результат", lines, 2.8)
    end
end

-- ===================== СЛОТЫ =====================
local SLOT_SYMBOLS = { "\u{1F352}", "\u{1F34B}", "\u{1F514}", "\u{2B50}", "7\u{20E3}" }
local SLOT_PAYOUT = { [3] = 10, [2] = 2 }

-- Барабаны увеличены настолько, насколько позволяет ширина экрана: три
-- карточки в ряд на 80 колонках физически не могут стать шире вдвое (не
-- поместятся), поэтому ширина увеличена умеренно, а символ дополнительно
-- обрамлён декоративными значками, чтобы визуально "весить" больше.
local REEL_W, REEL_H = 24, 7
local REEL_GAP = 2

local function reelLayout(ui)
    local w = ui.W or 80
    local totalW = REEL_W * 3 + REEL_GAP * 2
    local startX = math.floor((w - totalW) / 2)
    -- Сдвинуто на 1 строку вниз относительно прежнего (было 9), т.к. кнопка
    -- "Крутить" теперь стоит ниже (см. games.slots), чтобы не наезжать на
    -- легенду комбинаций строкой выше.
    local startY = 10
    return startX, startY
end

local function drawReel(ui, x, y, symbol, borderColor, dim)
    ui.panel(x, y, REEL_W, REEL_H, borderColor, ui.COLOR.WINDOW_BG)
    -- Декоративное обрамление символа - настоящий размер шрифта не
    -- увеличить, но значки по бокам делают символ заметнее в крупной карточке.
    local big = "\u{2726} " .. symbol .. " \u{2726}"
    local sx = centerIn(x, REEL_W, big)
    local sy = y + math.floor((REEL_H - 1) / 2)
    ui.text(sx, sy, big, dim and ui.COLOR.TEXT_MUTED or ui.COLOR.TEXT_LIGHT, ui.COLOR.WINDOW_BG)
end

local function drawReels(ui, symbols, spinning)
    local startX, startY = reelLayout(ui)
    for i = 1, 3 do
        local x = startX + (i - 1) * (REEL_W + REEL_GAP)
        drawReel(ui, x, startY, symbols[i], spinning and ui.COLOR.ACCENT_GOLD_DIM or ui.COLOR.ACCENT_GOLD, spinning)
    end
    return startX, startY
end

function games.slots(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    local idleSymbols = { SLOT_SYMBOLS[1], SLOT_SYMBOLS[2], SLOT_SYMBOLS[3] }

    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        drawHeader(ui, "СЛОТЫ", balance, walletLabel, currentBet)

        -- Пояснение комбинаций - раньше было непонятно, за что платят (в
        -- костях/монетке множитель написан прямо на кнопке выбора).
        local legend = "3 одинаковых символа = x" .. SLOT_PAYOUT[3] ..
            "    2 одинаковых = x" .. SLOT_PAYOUT[2]
        ui.centerText(5, legend, ui.COLOR.TEXT_MUTED)

        -- Кнопка "Крутить" опущена на 1 строку ниже прежнего места (была y=6)
        -- - между легендой и кнопкой появилась пустая строка-буфер (была
        -- строка впритык к тексту, отсюда ощущение, что они наезжают друг
        -- на друга). Барабаны (reelLayout) соответственно тоже сдвинуты вниз.
        local spinW, spinH = 34, 3
        local spinX = math.floor((ui.W - spinW) / 2)
        local spinBtn = ui.button(spinX, 7, spinW, spinH, "\u{1F3B0} КРУТИТЬ", ui.COLOR.BTN_BG_GOLD)

        drawReels(ui, idleSymbols, false)

        local betBtns = drawBetUI(ui, currentBet)

        local tx, ty = ui.waitTouch(60)
        if not tx then return end -- таймаут неактивности

        local exitClicked
        currentBet, exitClicked = handleBetClick(ui, tx, ty, betBtns, currentBet)
        if exitClicked then return end

        if ui.hit(spinBtn, tx, ty) then
            if validateBet(ui, currentBet, balance) then
                -- Крупная анимация прокрутки - три золочёные карточки-барабана,
                -- кадров стало больше - анимация ощутимо длиннее.
                for i = 1, 18 do
                    local r = {
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                        SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    }
                    drawReels(ui, r, true)
                    os.sleep(0.08)
                end

                local reels = {
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                    SLOT_SYMBOLS[math.random(#SLOT_SYMBOLS)],
                }
                drawReels(ui, reels, false)
                idleSymbols = reels

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
                    showRoundResult(ui, win, { "Комбинация собрана!", "Выигрыш: +" .. win, "Баланс: " .. balance })
                else
                    showRoundResult(ui, 0, { "В этот раз без выигрыша.", "Баланс: " .. balance })
                end
            end
        end
    end
end

-- ===================== КОСТИ =====================
-- Раскладка точек на кости 1-6 в сетке 3x3 (строка, столбец)
local DICE_PIPS = {
    [1] = { {2,2} },
    [2] = { {1,1}, {3,3} },
    [3] = { {1,1}, {2,2}, {3,3} },
    [4] = { {1,1}, {1,3}, {3,1}, {3,3} },
    [5] = { {1,1}, {1,3}, {2,2}, {3,1}, {3,3} },
    [6] = { {1,1}, {2,1}, {3,1}, {1,3}, {2,3}, {3,3} },
}

-- Кости расширены и стали выше прежнего: по горизонтали места на экране
-- много (всего 2 карточки в ряд), поэтому ширина увеличена заметнее, чем
-- у слотов (там 3 карточки делят ту же ширину).
local DIE_W, DIE_H = 20, 8
local DIE_GAP = 6

local function drawDie(ui, x, y, value, borderColor)
    ui.panel(x, y, DIE_W, DIE_H, borderColor, ui.COLOR.WINDOW_BG)
    local pips = DICE_PIPS[value] or {}
    local innerX, innerY = x + 2, y + 1
    local stepX = math.floor((DIE_W - 4) / 2)
    -- Раньше нижний ряд точек (row=3) вычислялся как innerY + 2*stepY, что
    -- при высоте карточки DIE_H попадало ровно НА нижнюю рамку панели (или
    -- за неё). Теперь нижний ряд явно ставится на 1 строку выше нижней
    -- рамки (innerY + (DIE_H - 3)), а средний ряд - посередине между
    -- верхним и нижним, так что все точки остаются строго внутри квадрата.
    local bottomOffset = DIE_H - 3
    local function rowOffset(row)
        if row == 1 then return 0 end
        if row == 3 then return bottomOffset end
        return math.floor(bottomOffset / 2)
    end
    for _, p in ipairs(pips) do
        local row, col = p[1], p[2]
        local px = innerX + (col - 1) * stepX
        local py = innerY + rowOffset(row)
        ui.text(px, py, "\u{25CF}", ui.COLOR.TEXT_LIGHT, ui.COLOR.WINDOW_BG)
    end
end

local function diceLayout(ui)
    local w = ui.W or 80
    local totalW = DIE_W * 2 + DIE_GAP
    local startX = math.floor((w - totalW) / 2)
    -- Кнопки выбора (Меньше/Ровно/Больше) стоят на y=6-8, поэтому кости
    -- начинаются сразу под ними и используют всю свободную высоту до
    -- панели ставок внизу (см. drawBetUI) - это и даёт увеличенную высоту.
    local startY = 9
    return startX, startY
end

local function drawDicePair(ui, d1, d2, borderColor)
    local startX, startY = diceLayout(ui)
    drawDie(ui, startX, startY, d1, borderColor)
    drawDie(ui, startX + DIE_W + DIE_GAP, startY, d2, borderColor)
end

function games.dice(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    local lastD1, lastD2 = 3, 4

    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        drawHeader(ui, "КОСТИ", balance, walletLabel, currentBet)

        local lessBox = ui.button(4, 6, 20, 3, "Меньше 7 (x2)", ui.COLOR.BTN_BG_PURPLE)
        local eqBox   = ui.button(28, 6, 20, 3, "Ровно 7 (x5)", ui.COLOR.BTN_BG_GOLD)
        local moreBox = ui.button(52, 6, 20, 3, "Больше 7 (x2)", ui.COLOR.BTN_BG_BLUE)

        drawDicePair(ui, lastD1, lastD2, ui.COLOR.ACCENT_GOLD)

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
                -- Крупная анимация броска - две золочёные кости с точками во весь блок,
                -- кадров стало больше - анимация ощутимо длиннее.
                for i = 1, 16 do
                    drawDicePair(ui, math.random(1, 6), math.random(1, 6), ui.COLOR.ACCENT_GOLD_DIM)
                    os.sleep(0.08)
                end

                local d1, d2 = math.random(1, 6), math.random(1, 6)
                local sum = d1 + d2
                drawDicePair(ui, d1, d2, ui.COLOR.ACCENT_GOLD)
                lastD1, lastD2 = d1, d2

                local win = 0
                if choice == "less" and sum < 7 then win = currentBet * 2 end
                if choice == "more" and sum > 7 then win = currentBet * 2 end
                if choice == "equal" and sum == 7 then win = currentBet * 5 end

                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then return end

                balance = result.balance
                local sumLine = "Кубики: " .. d1 .. " и " .. d2 .. "  (сумма: " .. sum .. ")"
                if win > 0 then
                    showRoundResult(ui, win, { sumLine, "Выигрыш: +" .. win, "Баланс: " .. balance })
                else
                    showRoundResult(ui, 0, { sumLine, "В этот раз без выигрыша.", "Баланс: " .. balance })
                end
            end
        end
    end
end

-- ===================== МОНЕТКА =====================
-- Монета - единственная карточка в ряд, поэтому ширина увеличена почти
-- до предела экрана (при сохранении отступов по краям).
local COIN_W, COIN_H = 60, 8

local function drawCoin(ui, faceText, borderColor, dim)
    local w = ui.W or 80
    local x = math.floor((w - COIN_W) / 2)
    local y = 9
    ui.panel(x, y, COIN_W, COIN_H, borderColor, ui.COLOR.WINDOW_BG)
    local big = "\u{2726} \u{25C9}  " .. faceText .. "  \u{25C9} \u{2726}"
    -- floor(COIN_H/2) раньше клал текст на строку НИЖЕ истинного центра
    -- панели - теперь floor((COIN_H-1)/2) центрирует его точно.
    ui.text(centerIn(x, COIN_W, big), y + math.floor((COIN_H - 1) / 2), big,
        dim and ui.COLOR.TEXT_MUTED or ui.COLOR.TEXT_LIGHT, ui.COLOR.WINDOW_BG)
end

function games.coinflip(ui, net, bankAddr, nick, wallet, walletLabel, balance)
    local currentBet = math.max(config.MIN_BET, math.min(10, balance))
    local lastFace = "ОРЁЛ"

    while true do
        ui.clear(ui.COLOR.DESKTOP_BG)
        drawHeader(ui, "МОНЕТКА", balance, walletLabel, currentBet)

        local headsBox = ui.button(15, 6, 20, 3, "Орёл (x2)", ui.COLOR.BTN_BG_PURPLE)
        local tailsBox = ui.button(45, 6, 20, 3, "Решка (x2)", ui.COLOR.BTN_BG_BLUE)

        drawCoin(ui, lastFace, ui.COLOR.ACCENT_GOLD, false)

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
                -- Крупная анимация подкидывания - монета во всю карточку меняет грань,
                -- кадров стало больше - анимация ощутимо длиннее.
                local faces = {"ОРЁЛ", "РЕШКА"}
                for i = 1, 16 do
                    drawCoin(ui, faces[math.random(1, 2)], ui.COLOR.ACCENT_GOLD_DIM, true)
                    os.sleep(0.08)
                end

                local outcome = (math.random(1, 2) == 1) and "heads" or "tails"
                local outcomeText = outcome == "heads" and "ОРЁЛ" or "РЕШКА"
                drawCoin(ui, outcomeText, ui.COLOR.ACCENT_GOLD, false)
                lastFace = outcomeText

                local win = (choice == outcome) and (currentBet * 2) or 0

                local ok, result = settle(net, bankAddr, nick, wallet, currentBet, win)
                if not ok then return end

                balance = result.balance
                local faceLine = "Выпало: " .. outcomeText
                if win > 0 then
                    showRoundResult(ui, win, { faceLine, "Выигрыш: +" .. win, "Баланс: " .. balance })
                else
                    showRoundResult(ui, 0, { faceLine, "В этот раз без выигрыша.", "Баланс: " .. balance })
                end
            end
        end
    end
end

return games