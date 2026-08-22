-- ui.lua
-- Тач-интерфейс для монитора 160×50 (тир 3 GPU+Screen).
-- Оформление: тёмно-фиолетовое казино-сукно, золотые рамки, объёмные кнопки.

local component = require("component")
local computer  = require("computer")
local event     = require("event")
local unicode   = require("unicode")

local ui = {}

local ulen = unicode.len

local gpu = component.gpu
ui.gpu = gpu

-- ===================== ПАЛИТРА =====================
ui.COLOR = {
    -- фон
    DESKTOP_BG      = 0x0E0920,  -- очень тёмный фиолет (сукно)
    DESKTOP_BG2     = 0x16123A,  -- чуть светлее для текстуры
    TASKBAR_BG      = 0x07050F,
    -- окна/карточки
    WINDOW_BG       = 0x1A1535,
    WINDOW_TITLE    = 0x241E50,
    -- акценты
    ACCENT_GOLD     = 0xF0C060,
    ACCENT_GOLD_DIM = 0x7A6428,
    SHADOW          = 0x050310,
    -- текст
    TEXT_DARK       = 0x0E0920,
    TEXT_LIGHT      = 0xF5EEE0,
    TEXT_MUTED      = 0x8070A8,
    -- кнопки
    ICON_BG         = 0x251E50,
    BTN_BG          = 0x1E8A4A,   -- зелёный (совместимость)
    BTN_BG_2        = 0xA82820,   -- красный (ошибки / назад)
    BTN_BG_GOLD     = 0xB8841A,   -- золотой (главное действие)
    BTN_BG_PURPLE   = 0x5A2878,   -- фиолетовый (вариант A)
    BTN_BG_BLUE     = 0x1E5C8C,   -- синий (вариант B)
    BTN_BG_NEUTRAL  = 0x2A2450,   -- нейтральный (цифры, назад)
    BTN_TEXT        = 0xFFFFFF,
}

local W, H = 160, 50

-- ===================== ЦВЕТОВЫЕ УТИЛИТЫ =====================
local function clamp(v) return math.min(255, math.max(0, v)) end

local function shade(color, factor)
    local r = clamp(math.floor(((color >> 16) & 0xFF) * factor))
    local g = clamp(math.floor(((color >>  8) & 0xFF) * factor))
    local b = clamp(math.floor(( color        & 0xFF) * factor))
    return (r << 16) | (g << 8) | b
end

function ui.bind(screenAddress)
    gpu.bind(screenAddress)
    W, H = gpu.maxResolution()
    gpu.setResolution(W, H)
    ui.W, ui.H = W, H

    -- ===== Двойная буферизация =====
    -- Раньше каждая перерисовка (ui.clear + десятки gpu.fill/gpu.set) шла
    -- напрямую в видеопамять экрана, и пользователь видел промежуточные
    -- кадры (пустой фон, потом текст и т.д.) - отсюда мигание при каждом
    -- обновлении. Теперь рисуем в невидимый буфер той же величины, а на
    -- экран переносим его одним вызовом gpu.bitblt (ui.flip) - экран
    -- меняется атомарно, промежуточные кадры не видны.
    -- Если GPU не поддерживает доп. буферы (старая/слабая карта) - тихо
    -- откатываемся на прямую отрисовку, как было раньше.
    ui.buf = nil
    if gpu.allocateBuffer then
        local ok, buf = pcall(gpu.allocateBuffer, W, H)
        if ok and buf then
            ui.buf = buf
            gpu.setActiveBuffer(buf)
        end
    end

    return W, H
end

-- Переносит содержимое невидимого буфера на экран одним вызовом.
-- Вызывается автоматически из ui.waitTouch, поэтому в большинстве экранов
-- явно дёргать не нужно. Явно нужен только там, где кадры меняются БЕЗ
-- ожидания касания - например, в анимации вращения барабанов/костей.
function ui.flip()
    if ui.buf then
        gpu.bitblt(0, 1, 1, W, H, ui.buf, 1, 1)
    end
end

-- ===================== БАЗОВЫЕ ПРИМИТИВЫ =====================

function ui.rect(x, y, w, h, color)
    gpu.setBackground(color)
    gpu.fill(x, y, w, h, " ")
end

function ui.text(x, y, str, fg, bg)
    gpu.setForeground(fg or ui.COLOR.TEXT_LIGHT)
    if bg then gpu.setBackground(bg) end
    gpu.set(x, y, str)
end

function ui.centerText(cy, str, fg, bg)
    local x = math.max(1, math.floor((W - ulen(str)) / 2) + 1)
    ui.text(x, cy, str, fg, bg)
end

function ui.drawBorder(x, y, w, h, color, bg)
    bg = bg or ui.COLOR.WINDOW_BG
    gpu.setForeground(color)
    gpu.setBackground(bg)
    gpu.set(x, y, "\u{250C}" .. string.rep("\u{2500}", math.max(0, w - 2)) .. "\u{2510}")
    for i = 1, h - 2 do
        gpu.set(x,         y + i, "\u{2502}")
        gpu.set(x + w - 1, y + i, "\u{2502}")
    end
    gpu.set(x, y + h - 1, "\u{2514}" .. string.rep("\u{2500}", math.max(0, w - 2)) .. "\u{2518}")
end

local function dropShadow(x, y, w, h)
    if x + w <= W and y + h <= H then
        gpu.setBackground(ui.COLOR.SHADOW)
        gpu.fill(x + 1, y + 1, w, h, " ")
    end
end
ui.shadow = dropShadow

function ui.panel(x, y, w, h, borderColor, bg, flat)
    bg          = bg          or ui.COLOR.WINDOW_BG
    borderColor = borderColor or ui.COLOR.ACCENT_GOLD
    if not flat then dropShadow(x, y, w, h) end
    gpu.setBackground(bg)
    gpu.fill(x, y, w, h, " ")
    ui.drawBorder(x, y, w, h, borderColor, bg)
    return { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 }
end

-- Фон с текстурой и верхней линией
function ui.clear(color)
    color = color or ui.COLOR.DESKTOP_BG
    gpu.setBackground(color)
    gpu.fill(1, 1, W, H, " ")

    if color == ui.COLOR.DESKTOP_BG then
        gpu.setForeground(ui.COLOR.DESKTOP_BG2)
        gpu.setBackground(color)
        for y = 3, H - 2, 2 do
            local offset = (math.floor(y / 2) % 2 == 0) and 0 or 4
            for x = 3 + offset, W - 1, 8 do
                gpu.set(x, y, "\u{00B7}")
            end
        end
        gpu.setForeground(ui.COLOR.ACCENT_GOLD_DIM)
        gpu.setBackground(color)
        gpu.set(1, 1, string.rep("\u{2550}", W))
    end

    gpu.setBackground(color)
    gpu.setForeground(ui.COLOR.TEXT_LIGHT)
end

-- Объёмная кнопка с бликом сверху и тенью снизу
function ui.button(x, y, w, h, label, bgColor, fgColor, flat)
    bgColor = bgColor or ui.COLOR.BTN_BG
    fgColor = fgColor or ui.COLOR.BTN_TEXT

    if not flat then dropShadow(x, y, w, h) end

    gpu.setBackground(bgColor)
    gpu.fill(x, y, w, h, " ")

    if h >= 2 then
        gpu.setBackground(shade(bgColor, 1.35))
        gpu.fill(x, y, w, 1, " ")
        gpu.setBackground(shade(bgColor, 0.65))
        gpu.fill(x, y + h - 1, w, 1, " ")
    end

    local tx = x + math.max(0, math.floor((w - ulen(label)) / 2))
    local ty = y + math.floor((h - 1) / 2)
    gpu.setForeground(fgColor)
    gpu.setBackground(bgColor)
    gpu.set(tx, ty, label)

    return { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 }
end

function ui.hit(box, tx, ty)
    return tx >= box.x1 and tx <= box.x2 and ty >= box.y1 and ty <= box.y2
end

-- ===================== СЕССИЯ / ОЖИДАНИЕ КАСАНИЯ =====================
ui.session = { nick = nil, left = false }

function ui.waitTouch(timeout)
    -- Кадр к этому моменту уже полностью нарисован в буфере (если он есть) -
    -- переносим его на экран одним блитом перед тем, как ждать касание.
    ui.flip()

    local deadline = computer.uptime() + timeout
    while true do
        local remaining = deadline - computer.uptime()
        if remaining <= 0 then return nil end
        local ev, a1, a2, a3 = event.pull(math.min(remaining, 1))
        if ev == "touch" then
            return a2, a3
        elseif ev == "player_off" and ui.session.nick and a1 == ui.session.nick then
            ui.session.left = true
            return nil
        end
    end
end

-- ===================== ВЕРХНЯЯ ПАНЕЛЬ (taskbar) =====================
-- На 160 колонках помещаем ник слева и оба баланса справа без наездов.
function ui.taskbar(nick, chips, credits)
    gpu.setBackground(ui.COLOR.TASKBAR_BG)
    gpu.fill(1, 1, W, 1, " ")
    gpu.setForeground(ui.COLOR.ACCENT_GOLD)
    gpu.set(3, 1, "\u{1F464} " .. nick)

    local balanceStr = string.format("\u{1F9F1} %d фишек    \u{1F49A} %d кредитов", chips, credits)
    gpu.setForeground(ui.COLOR.TEXT_LIGHT)
    gpu.set(W - ulen(balanceStr) - 1, 1, balanceStr)

    gpu.setForeground(ui.COLOR.ACCENT_GOLD_DIM)
    gpu.setBackground(ui.COLOR.DESKTOP_BG)
    gpu.set(1, 2, string.rep("\u{2500}", W))
end

-- ===================== ИКОНКИ РАБОЧЕГО СТОЛА =====================
local ICON_META = {
    slots    = { glyph = "\u{1F3B0}", accent = 0x6A2090 },
    dice     = { glyph = "\u{1F3B2}", accent = 0x8C2010 },
    deposit  = { glyph = "\u{2B06}",  accent = 0x187850 },
    withdraw = { glyph = "\u{2B07}",  accent = 0x185880 },
}
local DEFAULT_ICON_META = { glyph = "\u{2666}", accent = 0x404040 }

local function drawIconRow(out, list, startY, iconW, iconH, gapX)
    local totalW = #list * iconW + (#list - 1) * gapX
    local startX = math.max(1, math.floor((W - totalW) / 2))
    for i, icon in ipairs(list) do
        local x = startX + (i - 1) * (iconW + gapX)
        local y = startY
        if y + iconH - 1 <= H - 2 then
            local meta = ICON_META[icon.id] or DEFAULT_ICON_META

            dropShadow(x, y, iconW, iconH)

            gpu.setBackground(ui.COLOR.WINDOW_BG)
            gpu.fill(x, y, iconW, iconH, " ")

            -- цветная шапка карточки
            gpu.setBackground(meta.accent)
            gpu.fill(x, y, iconW, 2, " ")

            -- нижняя линия-подчёркивание карточки
            gpu.setForeground(shade(meta.accent, 0.75))
            gpu.setBackground(ui.COLOR.WINDOW_BG)
            gpu.set(x, y + iconH - 1, string.rep("\u{2500}", iconW))

            -- глиф в центре карточки
            local gx = x + math.max(0, math.floor((iconW - ulen(meta.glyph)) / 2))
            gpu.setForeground(ui.COLOR.TEXT_LIGHT)
            gpu.setBackground(ui.COLOR.WINDOW_BG)
            gpu.set(gx, y + 3, meta.glyph)

            -- подпись
            local lx = x + math.max(0, math.floor((iconW - ulen(icon.label)) / 2))
            gpu.set(lx, y + 5, icon.label)

            out[#out + 1] = { id = icon.id, box = { x1 = x, y1 = y, x2 = x + iconW - 1, y2 = y + iconH - 1 } }
        end
    end
end

-- ===================== РАБОЧИЙ СТОЛ =====================
-- Раскладка для 160×50:
--   строка 1     - taskbar
--   строка 2     - разделитель
--   строки 6-17  - иконки игр (iconH=10)
--   строка 30    - подпись "КАССА"
--   строки 31-42 - иконки кассы
--   строка 50    - подсказка внизу
function ui.desktop(nick, chips, credits, icons)
    ui.clear(ui.COLOR.DESKTOP_BG)
    ui.taskbar(nick, chips, credits)

    local hitboxes = {}
    local iconW, iconH = 26, 10
    local gapX = 4

    local gameIcons, kassaIcons = {}, {}
    for _, icon in ipairs(icons) do
        if icon.id == "deposit" or icon.id == "withdraw" then
            kassaIcons[#kassaIcons + 1] = icon
        else
            gameIcons[#gameIcons + 1] = icon
        end
    end

    -- Игры - одна строка карточек
    drawIconRow(hitboxes, gameIcons, 6, iconW, iconH, gapX)

    -- Касса - отдельный блок со своим заголовком
    if #kassaIcons > 0 then
        local kassaIconY = 30
        ui.centerText(kassaIconY - 3, "\u{2014}\u{2014}\u{2014}  К А С С А  \u{2014}\u{2014}\u{2014}", ui.COLOR.ACCENT_GOLD_DIM, ui.COLOR.DESKTOP_BG)
        drawIconRow(hitboxes, kassaIcons, kassaIconY, iconW, iconH, gapX)
    end

    -- Нижняя строка-подсказка
    gpu.setBackground(ui.COLOR.TASKBAR_BG)
    gpu.fill(1, H, W, 1, " ")
    gpu.setForeground(ui.COLOR.TEXT_MUTED)
    gpu.set(3, H, "\u{2726} Коснитесь иконки, чтобы открыть")

    return hitboxes
end

-- ===================== МОДАЛЬНОЕ ОКНО =====================
function ui.messageBox(title, lines, timeout)
    -- Ограничиваем 70% ширины, чтобы окно не занимало весь экран
    local w = math.min(math.floor(W * 0.55), 90)
    local h = #lines + 7
    local x = math.floor((W - w) / 2)
    local y = math.floor((H - h) / 2)

    local lowered = title:lower()
    local borderColor = ui.COLOR.ACCENT_GOLD
    local icon = "\u{2666}"
    if lowered:find("ошиб") or lowered:find("критич") or lowered:find("недостат") or lowered:find("не удал") then
        borderColor, icon = ui.COLOR.BTN_BG_2, "\u{26A0}"
    elseif lowered:find("выигрыш") or lowered:find("выполнен") then
        borderColor, icon = ui.COLOR.BTN_BG, "\u{2728}"
    end

    dropShadow(x, y, w, h)
    gpu.setBackground(ui.COLOR.WINDOW_BG)
    gpu.fill(x, y, w, h, " ")
    ui.drawBorder(x, y, w, h, borderColor)

    gpu.setBackground(borderColor)
    gpu.fill(x + 1, y + 1, w - 2, 1, " ")
    gpu.setForeground(ui.COLOR.TEXT_DARK)
    gpu.set(x + 3, y + 1, icon .. "  " .. title)

    for i, line in ipairs(lines) do
        gpu.setForeground(ui.COLOR.TEXT_LIGHT)
        gpu.setBackground(ui.COLOR.WINDOW_BG)
        gpu.set(x + 3, y + 2 + i, line)
    end

    local okBox = ui.button(x + math.floor(w / 2) - 8, y + h - 2, 16, 1, "\u{2713}  ОК", ui.COLOR.BTN_BG, ui.COLOR.TEXT_LIGHT, true)

    local deadline = timeout and (computer.uptime() + timeout) or nil
    while true do
        local remaining = deadline and (deadline - computer.uptime()) or 5
        if deadline and remaining <= 0 then return end
        local tx, ty = ui.waitTouch(remaining)
        if tx and ui.hit(okBox, tx, ty) then return end
        if not tx and deadline then return end
    end
end

-- ===================== ЦИФРОВАЯ КЛАВИАТУРА =====================
function ui.numpad(title, maxDigits)
    maxDigits = maxDigits or 8

    -- Точный расчёт высоты (компактная раскладка, с запасом от краёв экрана):
    -- строки 1-2      : заголовок + крестик (h=2 - крестику нужна высота 2, чтобы
    --                    по нему было легко попасть тачем, а не только в 1 строку)
    -- строка 3        : отступ
    -- строки 4-5      : LCD (h=2)
    -- строка 6        : отступ
    -- строки 7-17     : клавиши 4 ряда × (kh=2 + gap=1), последний ряд без гэпа снизу
    -- строка 18       : отступ
    -- строки 19-21    : кнопка "Подтвердить" (h=3)
    -- строка 22       : нижняя рамка
    -- итого h = 23 (было 26 - ужали, чтобы гарантированно помещалось и не резалось)
    -- x-отступы: рамка + 2 = 3; 3 колонки по kw=12 + gap=1: 3*12+2=38; 44-38=6, по 3 с каждой стороны
    local w, h = 44, 23
    local x = math.floor((W - w) / 2)
    local y = math.max(1, math.floor((H - h) / 2))
    local value = ""

    -- closeBox нужен снаружи redraw для hit-теста, объявляем здесь
    local closeBox, okBox, boxes

    local function redraw()
        dropShadow(x, y, w, h)
        gpu.setBackground(ui.COLOR.WINDOW_BG)
        gpu.fill(x, y, w, h, " ")
        ui.drawBorder(x, y, w, h, ui.COLOR.ACCENT_GOLD)

        -- Заголовок (строки y+1..y+2, высота 2)
        gpu.setBackground(ui.COLOR.ACCENT_GOLD)
        gpu.fill(x + 1, y + 1, w - 2, 2, " ")
        gpu.setForeground(ui.COLOR.TEXT_DARK)
        gpu.set(x + 3, y + 1, title:sub(1, w - 10))

        -- Крестик: высота 2 (как в заголовке) - реально легче попасть тачем
        closeBox = ui.button(x + w - 6, y + 1, 5, 2, "\u{2715}", ui.COLOR.BTN_BG_2, ui.COLOR.TEXT_LIGHT, true)

        -- LCD-табло (строки y+4 .. y+5)
        gpu.setBackground(0x080808)
        gpu.fill(x + 2, y + 4, w - 4, 2, " ")
        local shown = (value == "" and "0" or value)
        local lcdInnerW = w - 4
        local numX = x + 2 + math.max(0, math.floor((lcdInnerW - ulen(shown)) / 2))
        gpu.setForeground(0x39FF6A)
        gpu.setBackground(0x080808)
        gpu.set(numX, y + 5, shown)

        -- Клавиши: 3 колонки × 4 ряда, kw=12, kh=2, colGap=1, rowGap=1
        -- kx0 = x+3; ряды начинаются с y+7
        -- ряд 0: y+7..y+8, ряд 1: y+10..y+11, ряд 2: y+13..y+14, ряд 3: y+16..y+17
        boxes = {}
        local keys = { "7","8","9", "4","5","6", "1","2","3", "C","0","\u{2190}" }
        local kw, kh = 12, 2
        local kx0 = x + 3
        local ky0 = y + 7
        for i, k in ipairs(keys) do
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            local kx = kx0 + col * (kw + 1)
            local ky = ky0 + row * (kh + 1)
            local keyColor = (k == "C") and ui.COLOR.BTN_BG_2 or ui.COLOR.BTN_BG_NEUTRAL
            local box = ui.button(kx, ky, kw, kh, k, keyColor, ui.COLOR.TEXT_LIGHT, true)
            boxes[#boxes + 1] = { key = (k == "\u{2190}") and "<" or k, box = box }
        end

        -- "Подтвердить": строки y+19..y+21 (ниже последнего ряда y+16..y+17, отступ 1)
        okBox = ui.button(x + 2, y + 19, w - 4, 3, "\u{2713}  Подтвердить", ui.COLOR.BTN_BG_GOLD, ui.COLOR.TEXT_LIGHT, true)
    end

    local needsRedraw = true
    while true do
        if needsRedraw then
            redraw()
            needsRedraw = false
        end
        local tx, ty = ui.waitTouch(60)
        if not tx then return nil end
        -- Крестик - проверяем первым, до всех остальных хитбоксов
        if closeBox and ui.hit(closeBox, tx, ty) then
            return nil
        elseif okBox and ui.hit(okBox, tx, ty) then
            local n = tonumber(value)
            if n and n > 0 then return math.floor(n) end
        else
            if boxes then
                for _, b in ipairs(boxes) do
                    if ui.hit(b.box, tx, ty) then
                        if b.key == "C" then
                            value = ""
                        elseif b.key == "<" then
                            value = value:sub(1, -2)
                        else
                            if #value < maxDigits then value = value .. b.key end
                        end
                        needsRedraw = true
                        break
                    end
                end
            end
        end
    end
end

return ui
