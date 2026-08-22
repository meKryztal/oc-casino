-- ui.lua
-- Тач-интерфейс "рабочий стол" для монитора станции (тир 2/3 GPU+Screen).
-- Оформление: тёмно-гранатовый фон казино, золотые рамки, объёмные кнопки
-- с тенью и бликом, карточки-иконки с цветным акцентом, LCD-табло на вводе
-- суммы. Никакой текстовой командной строки игрок никогда не увидит.

local component = require("component")
local computer = require("computer")
local event = require("event")
local unicode = require("unicode")

local ui = {}

-- ВАЖНО: везде, где считаем ширину строки для центрирования/выравнивания,
-- используем unicode.len(), а НЕ #str. У кириллицы в UTF-8 по 2 байта на
-- символ, у эмодзи 3-4 байта - #str даёт длину в байтах и все надписи
-- смещались от истинного центра. unicode.len() даёт правильное число символов.
local ulen = unicode.len

local gpu = component.gpu
ui.gpu = gpu

-- ===================== ПАЛИТРА =====================
ui.COLOR = {
    -- фон
    DESKTOP_BG   = 0x140F26, -- глубокий тёмно-фиолетовый (сукно стола)
    DESKTOP_BG2  = 0x1E1740, -- чуть светлее, для лёгкой текстуры фона
    TASKBAR_BG   = 0x0D0A1A,
    -- окна/карточки
    WINDOW_BG    = 0x201A3D,
    WINDOW_TITLE = 0x2B2158,
    -- акценты
    ACCENT_GOLD  = 0xE8C468,
    ACCENT_GOLD_DIM = 0x8A7440,
    SHADOW       = 0x070512,
    -- текст
    TEXT_DARK    = 0x120C24,
    TEXT_LIGHT   = 0xF3EEDD,
    TEXT_MUTED   = 0x8D84B0,
    -- кнопки (совместимость со старым кодом + новые)
    ICON_BG      = 0x2A2154,
    BTN_BG       = 0x2E9E5B, -- зелёный (оставлен для совместимости, в новых экранах не используется)
    BTN_BG_2     = 0xC0392B, -- красный (используется только в messageBox для ошибок)
    BTN_BG_GOLD  = 0xC9962C, -- основное "золотое" действие (крутить/подтвердить/внести)
    BTN_BG_PURPLE= 0x6C3483, -- вторичный выбор в играх (вариант A)
    BTN_BG_BLUE  = 0x2C6E9E, -- вторичный выбор в играх (вариант B)
    BTN_BG_NEUTRAL = 0x342C5C, -- нейтральные/служебные кнопки (назад, цифры, пресеты ставок)
    BTN_TEXT     = 0xFFFFFF,
}

local W, H = 80, 25

-- ===================== ЦВЕТОВЫЕ УТИЛИТЫ =====================
local function clamp(v) return math.min(255, math.max(0, v)) end

local function shade(color, factor)
    local r = clamp(math.floor(((color >> 16) & 0xFF) * factor))
    local g = clamp(math.floor(((color >> 8) & 0xFF) * factor))
    local b = clamp(math.floor((color & 0xFF) * factor))
    return (r << 16) | (g << 8) | b
end

function ui.bind(screenAddress)
    gpu.bind(screenAddress)
    W, H = gpu.maxResolution()
    gpu.setResolution(W, H)
    ui.W, ui.H = W, H
    return W, H
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

-- Тонкая рамка одинарной линией (для окон/карточек)
function ui.drawBorder(x, y, w, h, color, bg)
    bg = bg or ui.COLOR.WINDOW_BG
    gpu.setForeground(color)
    gpu.setBackground(bg)
    gpu.set(x, y, "\u{250C}" .. string.rep("\u{2500}", math.max(0, w - 2)) .. "\u{2510}")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "\u{2502}")
        gpu.set(x + w - 1, y + i, "\u{2502}")
    end
    gpu.set(x, y + h - 1, "\u{2514}" .. string.rep("\u{2500}", math.max(0, w - 2)) .. "\u{2518}")
end

-- Отбрасывает лёгкую тень вправо-вниз от прямоугольника (если помещается на экране)
local function dropShadow(x, y, w, h)
    if x + w <= W and y + h <= H then
        gpu.setBackground(ui.COLOR.SHADOW)
        gpu.fill(x + 1, y + 1, w, h, " ")
    end
end
ui.shadow = dropShadow

-- Крупная карточка-панель (рамка + тень + заливка) - переиспользуемый "кирпичик"
-- для больших визуальных блоков (барабаны слотов, кубики, монета и т.п.),
-- чтобы не городить отдельную вёрстку в каждой мини-игре.
-- flat=true - без тени (для плотных сеток).
function ui.panel(x, y, w, h, borderColor, bg, flat)
    bg = bg or ui.COLOR.WINDOW_BG
    borderColor = borderColor or ui.COLOR.ACCENT_GOLD
    if not flat then dropShadow(x, y, w, h) end
    gpu.setBackground(bg)
    gpu.fill(x, y, w, h, " ")
    ui.drawBorder(x, y, w, h, borderColor, bg)
    return { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 }
end

-- Фон "рабочего стола": заливка + едва заметная текстура сукна + золотая окантовка сверху
function ui.clear(color)
    color = color or ui.COLOR.DESKTOP_BG
    gpu.setBackground(color)
    gpu.fill(1, 1, W, H, " ")

    if color == ui.COLOR.DESKTOP_BG then
        gpu.setForeground(ui.COLOR.DESKTOP_BG2)
        gpu.setBackground(color)
        for y = 3, H - 2, 2 do
            local offset = (math.floor(y / 2) % 2 == 0) and 0 or 3
            for x = 2 + offset, W - 1, 6 do
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

-- Объёмная кнопка с тенью и бликом сверху. flat=true - плоский вариант без тени
-- (для плотных сеток, где тени соседних кнопок накладывались бы друг на друга).
function ui.button(x, y, w, h, label, bgColor, fgColor, flat)
    bgColor = bgColor or ui.COLOR.BTN_BG
    fgColor = fgColor or ui.COLOR.BTN_TEXT

    if not flat then
        dropShadow(x, y, w, h)
    end

    gpu.setBackground(bgColor)
    gpu.fill(x, y, w, h, " ")

    if h >= 2 then
        gpu.setBackground(shade(bgColor, 1.35))
        gpu.fill(x, y, w, 1, " ")
        gpu.setBackground(shade(bgColor, 0.65))
        gpu.fill(x, y + h - 1, w, 1, " ")
    end

    local tx = x + math.max(0, math.floor((w - ulen(label)) / 2))
    -- floor(h/2) для чётной высоты давал строку НИЖЕ истинного центра
    -- (например при h=4 текст падал на 3-ю из 4 строк) - из-за этого текст
    -- "плыл" вниз в зелёных кнопках кассы и в "Обновить"/"Отмена".
    -- floor((h-1)/2) центрирует одинаково корректно и для чётной, и для
    -- нечётной высоты.
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
    local deadline = computer.uptime() + timeout
    while true do
        local remaining = deadline - computer.uptime()
        if remaining <= 0 then return nil end
        -- touch: (name, screenAddress, x, y, button, playerName) -> a1=address, a2=x, a3=y
        -- player_on/player_off: (name, nick) -> a1=nick
        local ev, a1, a2, a3 = event.pull(math.min(remaining, 1))
        if ev == "touch" then
            return a2, a3
        elseif ev == "player_off" and ui.session.nick and a1 == ui.session.nick then
            ui.session.left = true
            return nil
        end
    end
end

-- ===================== ВЕРХНЯЯ ПАНЕЛЬ =====================
function ui.taskbar(nick, chips, credits)
    gpu.setBackground(ui.COLOR.TASKBAR_BG)
    gpu.fill(1, 1, W, 1, " ")
    gpu.setForeground(ui.COLOR.ACCENT_GOLD)
    gpu.set(2, 1, "\u{1F464} " .. nick)

    -- В Unicode нет отдельного эмодзи "слиток", поэтому для ресурсов (chips)
    -- используем 🧱 как ближайший по виду блочный символ, а для валюты
    -- сервера (credits) - 💚 вместо прежнего 💎 (эмеральд).
    local balanceStr = string.format("\u{1F9F1} %d    \u{1F49A} %d", chips, credits)
    gpu.setForeground(ui.COLOR.TEXT_LIGHT)
    gpu.set(math.max(2, W - ulen(balanceStr) - 1), 1, balanceStr)

    gpu.setForeground(ui.COLOR.ACCENT_GOLD_DIM)
    gpu.setBackground(ui.COLOR.DESKTOP_BG)
    gpu.set(1, 2, string.rep("\u{2500}", W))
    gpu.setBackground(ui.COLOR.DESKTOP_BG)
end

-- Метаданные для карточек-иконок: глиф + акцентный цвет каждой категории
local ICON_META = {
    slots    = { glyph = "\u{1F3B0}", accent = 0x8E44AD },
    dice     = { glyph = "\u{1F3B2}", accent = 0xC0392B },
    coinflip = { glyph = "\u{1F4B0}", accent = 0xD4AF37 },
    deposit  = { glyph = "\u{2B06}",  accent = 0x27AE60 },
    withdraw = { glyph = "\u{2B07}",  accent = 0x2980B9 },
}
local DEFAULT_ICON_META = { glyph = "\u{2666}", accent = 0x555555 }

-- Рисует одну строку карточек-иконок, центрированную по ширине экрана.
-- Вынесено отдельно, чтобы одинаково рисовать и сетку игр, и отдельный
-- ряд кассы. Возвращает добавленные хитбоксы (уже кладёт их в out).
local function drawIconRow(out, list, startY, iconW, iconH, gapX)
    local totalW = #list * iconW + (#list - 1) * gapX
    local startX = math.max(1, math.floor((W - totalW) / 2))
    for i, icon in ipairs(list) do
        local x = startX + (i - 1) * (iconW + gapX)
        local y = startY
        if y + iconH <= H - 1 then
            local meta = ICON_META[icon.id] or DEFAULT_ICON_META

            dropShadow(x, y, iconW, iconH)

            gpu.setBackground(ui.COLOR.WINDOW_BG)
            gpu.fill(x, y, iconW, iconH, " ")
            gpu.setBackground(meta.accent)
            gpu.fill(x, y, iconW, 1, " ")

            gpu.setForeground(shade(meta.accent, 0.85))
            gpu.setBackground(ui.COLOR.WINDOW_BG)
            gpu.set(x, y + iconH - 1, string.rep("\u{2500}", iconW))

            local gx = x + math.floor((iconW - ulen(meta.glyph)) / 2)
            gpu.setForeground(ui.COLOR.TEXT_LIGHT)
            gpu.set(gx, y + 2, meta.glyph)

            local lx = x + math.max(0, math.floor((iconW - ulen(icon.label)) / 2))
            gpu.set(lx, y + 4, icon.label)

            out[#out + 1] = { id = icon.id, box = { x1 = x, y1 = y, x2 = x + iconW - 1, y2 = y + iconH - 1 } }
        end
    end
end

-- "Рабочий стол": заголовок, сетка игр сверху, и отдельным, явно
-- отличимым блоком снизу по центру - касса (внести/вывести), с подписью.
function ui.desktop(nick, chips, credits, icons)
    ui.clear(ui.COLOR.DESKTOP_BG)
    ui.taskbar(nick, chips, credits)
    ui.centerText(4, "\u{2666} К А З И Н О \u{2666}", ui.COLOR.ACCENT_GOLD, ui.COLOR.DESKTOP_BG)

    local hitboxes = {}
    local iconW, iconH = 16, 6
    local gapX, gapY = 3, 2

    -- Разделяем на игры и кассу (внести/вывести) - касса больше не мешается
    -- в общей сетке, а идёт отдельным блоком внизу.
    local gameIcons, kassaIcons = {}, {}
    for _, icon in ipairs(icons) do
        if icon.id == "deposit" or icon.id == "withdraw" then
            kassaIcons[#kassaIcons + 1] = icon
        else
            gameIcons[#gameIcons + 1] = icon
        end
    end

    local startX = 4
    local perRow = math.max(1, math.floor((W - startX) / (iconW + gapX)))
    local startY = 7
    for i = 1, #gameIcons, perRow do
        local rowItems = {}
        for j = i, math.min(i + perRow - 1, #gameIcons) do
            rowItems[#rowItems + 1] = gameIcons[j]
        end
        drawIconRow(hitboxes, rowItems, startY, iconW, iconH, gapX)
        startY = startY + iconH + gapY
    end

    if #kassaIcons > 0 then
        -- Заголовок "КАССА" поднят на 1 строку выше прежнего (было kassaY-1,
        -- впритык к верхнему краю карточек) - теперь между текстом и
        -- иконками есть пустая строка-буфер, и подпись не сидит на кнопках.
        local kassaY = H - iconH - 3
        ui.centerText(kassaY - 2, "\u{2666} К А С С А \u{2666}", ui.COLOR.ACCENT_GOLD_DIM, ui.COLOR.DESKTOP_BG)
        drawIconRow(hitboxes, kassaIcons, kassaY, iconW, iconH, gapX)
    end

    gpu.setBackground(ui.COLOR.TASKBAR_BG)
    gpu.fill(1, H, W, 1, " ")
    gpu.setForeground(ui.COLOR.TEXT_MUTED)
    gpu.set(2, H, "\u{2726} Коснитесь иконки, чтобы открыть")

    return hitboxes
end

-- Модальное окно-сообщение. Цвет рамки зависит от смысла заголовка:
-- золото - нейтрально, зелёный - выигрыш/успех, красный - ошибка.
function ui.messageBox(title, lines, timeout)
    local w = math.min(W - 6, 54)
    local h = #lines + 7
    local x, y = math.floor((W - w) / 2), math.floor((H - h) / 2)

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
    gpu.set(x + 2, y + 1, icon .. " " .. title)

    for i, line in ipairs(lines) do
        gpu.setForeground(ui.COLOR.TEXT_LIGHT)
        gpu.setBackground(ui.COLOR.WINDOW_BG)
        gpu.set(x + 2, y + 2 + i, line)
    end

    local okBox = ui.button(x + math.floor(w / 2) - 6, y + h - 2, 12, 1, "\u{2713} ОК", ui.COLOR.BTN_BG, ui.COLOR.TEXT_LIGHT, true)

    local deadline = timeout and (computer.uptime() + timeout) or nil
    while true do
        local remaining = deadline and (deadline - computer.uptime()) or 5
        if deadline and remaining <= 0 then return end
        local tx, ty = ui.waitTouch(remaining)
        if tx and ui.hit(okBox, tx, ty) then return end
        if not tx and deadline then return end
    end
end

-- Экранная цифровая клавиатура с LCD-табло. Возвращает число или nil (отмена).
function ui.numpad(title, maxDigits)
    maxDigits = maxDigits or 6
    local w, h = 26, 17
    local x, y = math.floor((W - w) / 2), math.floor((H - h) / 2)
    local value = ""

    local function redraw()
        dropShadow(x, y, w, h)
        gpu.setBackground(ui.COLOR.WINDOW_BG)
        gpu.fill(x, y, w, h, " ")
        ui.drawBorder(x, y, w, h, ui.COLOR.ACCENT_GOLD)

        gpu.setBackground(ui.COLOR.ACCENT_GOLD)
        gpu.fill(x + 1, y + 1, w - 2, 1, " ")
        gpu.setForeground(ui.COLOR.TEXT_DARK)
        gpu.set(x + 2, y + 1, title:sub(1, w - 6))

        -- крестик закрытия окна ввода суммы (в правом верхнем углу заголовка)
        local closeBox = ui.button(x + w - 3, y + 1, 2, 1, "\u{2715}", ui.COLOR.BTN_BG_2, ui.COLOR.TEXT_LIGHT, true)

        -- LCD-табло введённого значения
        gpu.setBackground(0x0A0A0A)
        gpu.fill(x + 2, y + 3, w - 4, 1, " ")
        local shown = (value == "" and "0" or value)
        gpu.setForeground(0x39FF6A)
        gpu.set(x + w - 3 - ulen(shown), y + 3, shown)

        local boxes = {}
        local keys = { "7", "8", "9", "4", "5", "6", "1", "2", "3", "C", "0", "\u{2190}" }
        local kw, kh = 6, 1
        local kx0, ky0 = x + 2, y + 5
        for i, k in ipairs(keys) do
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            local kx = kx0 + col * (kw + 1)
            local ky = ky0 + row * (kh + 1)
            local keyColor = (k == "C") and ui.COLOR.BTN_BG_2 or 0x342C5C
            local box = ui.button(kx, ky, kw, kh, k, keyColor, ui.COLOR.TEXT_LIGHT, true)
            boxes[#boxes + 1] = { key = (k == "\u{2190}") and "<" or k, box = box }
        end

        local okBox = ui.button(x + 2, y + h - 2, w - 4, 1, "\u{2713} Подтвердить", ui.COLOR.BTN_BG, ui.COLOR.TEXT_LIGHT, true)
        return boxes, okBox, closeBox
    end

    while true do
        local boxes, okBox, closeBox = redraw()
        local tx, ty = ui.waitTouch(60)
        if not tx then return nil end
        if ui.hit(closeBox, tx, ty) then
            return nil
        elseif ui.hit(okBox, tx, ty) then
            local n = tonumber(value)
            if n and n > 0 then return math.floor(n) end
        else
            for _, b in ipairs(boxes) do
                if ui.hit(b.box, tx, ty) then
                    if b.key == "C" then
                        value = ""
                    elseif b.key == "<" then
                        value = value:sub(1, -2)
                    else
                        if #value < maxDigits then value = value .. b.key end
                    end
                end
            end
        end
    end
end

return ui