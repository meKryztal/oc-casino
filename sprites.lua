-- sprites.lua
-- Общие пиксель-арт спрайты ('█'-блоки), используемые и в слотах, и в костях,
-- и на заставке казино. Один источник правды, чтобы не дублировать рисунки.

local unicode = require("unicode")
local ulen = unicode.len

local sprites = {}

-- ===================== МЕГА-ИКОНКИ (слоты / заставка) =====================
-- Высота всех иконок = 10 строк. Ширина у большинства 11, у "$" - 15.
sprites.MEGA = {
    ["7"] = {
        "███████████",
        "███████████",
        "        ███",
        "       ███ ",
        "      ███  ",
        "     ███   ",
        "    ███    ",
        "   ███     ",
        "   ███     ",
        "   ███     "
    },
    ["$"] = {
        "    ███████    ",
        "  ███████████  ",
        " ███       ███ ",
        " ███           ",
        "  █████████    ",
        "     █████████ ",
        "           ███ ",
        " ███       ███ ",
        "  ███████████  ",
        "    ███████    "
    },
    ["W"] = {
        "███     ███",
        "███     ███",
        "███     ███",
        "███  █  ███",
        "███ ███ ███",
        "█████ █████",
        "████   ████",
        "███     ███",
        "███     ███",
        "███     ███"
    },
    ["D"] = {
        "    ███    ",
        "   █████   ",
        "  ███████  ",
        " █████████ ",
        "███████████",
        " █████████ ",
        "  ███████  ",
        "   █████   ",
        "    ███    ",
        "     █     "
    },
    ["B"] = {
        "     █     ",
        "    ███    ",
        "   █████   ",
        "  ███████  ",
        " █████████ ",
        "███████████",
        "    ███    ",
        "   █████   ",
        "  ███████  ",
        "   █████   "
    },
}

sprites.MEGA_KEYS   = { "7", "$", "W", "D", "B" }
sprites.MEGA_COLORS = { 0xFFD700, 0xFF0000, 0x00FF00, 0x00FFFF, 0xFF00FF }
sprites.MEGA_H      = 10
-- Ширина самой широкой иконки ("$" = 15) - удобно для расчёта сетки барабанов/заставки.
sprites.MEGA_MAXW   = 15

-- Реальная ширина конкретной иконки (у большинства 11, у "$" 15) - нужна для точного центрирования.
function sprites.megaWidth(char)
    local matrix = sprites.MEGA[char]
    if not matrix then return 0 end
    local maxw = 0
    for _, line in ipairs(matrix) do
        local l = ulen(line)
        if l > maxw then maxw = l end
    end
    return maxw
end

-- Рисует мега-иконку левым верхним углом в (x, y).
function sprites.drawMega(gpu, char, x, y, color, bg)
    local matrix = sprites.MEGA[char]
    if not matrix then return end
    gpu.setForeground(color)
    if bg then gpu.setBackground(bg) end
    for i, line in ipairs(matrix) do
        gpu.set(x, y + i - 1, line)
    end
end

-- ===================== СПРАЙТ ОЧКА КОСТИ (вместо "●●") =====================
-- Высота 8 строк, ширина 13 - овал/кружок из блоков.
sprites.PIP = {
    "   ███████   ",
    " ███████████ ",
    "█████████████",
    "█████████████",
    "█████████████",
    "█████████████",
    " ███████████ ",
    "   ███████   "
}
sprites.PIP_W = 13
sprites.PIP_H = 8

function sprites.drawPip(gpu, x, y, color, bg)
    gpu.setForeground(color)
    if bg then gpu.setBackground(bg) end
    for i, line in ipairs(sprites.PIP) do
        gpu.set(x, y + i - 1, line)
    end
end

return sprites