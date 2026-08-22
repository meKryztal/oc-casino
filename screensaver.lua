-- screensaver.lua
-- Анимированная заставка (на основе 2.lua), которая показывается вместо
-- статичной надписи "Добро пожаловать", пока никто не встал на плиту.
-- Использует общие спрайты из sprites.lua (те же иконки, что и в слотах).
--
-- Как в оригинальном 2.lua: фон рисуется один раз (screensaver.start), а
-- дальше на каждом кадре (screensaver.update) обновляются только сами
-- символы - перерисовывать весь экран каждый раз не нужно.

local sprites = require("sprites")

local screensaver = {}

-- Как часто главный цикл должен вызывать screensaver.update(), чтобы
-- получилась анимация (главный цикл ждёт событие "player_on" с этим таймаутом).
screensaver.FRAME_DELAY = 0.6

local ICON_SLOT_W = sprites.MEGA_MAXW  -- 15 - фиксированный шаг между иконками
local ICON_GAP    = 4

-- Координаты области с иконками - вычисляются один раз в start() и переиспользуются в update().
local area = nil -- { x, y, w, h }

-- Рисует фон один раз (полная перерисовка экрана). Вызывается при входе в
-- режим ожидания (старт станции, выход из сессии игрока).
function screensaver.start(ui)
    local W, H = ui.W or 160, ui.H or 50

    ui.clear(ui.COLOR.DESKTOP_BG)

    local totalWidth = ICON_SLOT_W * 3 + ICON_GAP * 2
    local x = math.max(1, math.floor((W - totalWidth) / 2))
    local y = math.max(1, math.floor((H - sprites.MEGA_H) / 2))
    area = { x = x, y = y, w = totalWidth, h = sprites.MEGA_H }

    screensaver.update(ui)
end

-- Обновляет только область с символами (не трогая остальной экран).
function screensaver.update(ui)
    local gpu = ui.gpu
    if not area then
        -- update() вызвали раньше start() - откатываемся на полную инициализацию
        screensaver.start(ui)
        return
    end

    -- Очищаем только прямоугольник под иконками, весь остальной экран не трогаем.
    ui.rect(area.x, area.y, area.w, area.h, ui.COLOR.DESKTOP_BG)

    local c1 = sprites.MEGA_KEYS[math.random(#sprites.MEGA_KEYS)]
    local c2 = sprites.MEGA_KEYS[math.random(#sprites.MEGA_KEYS)]
    local c3 = sprites.MEGA_KEYS[math.random(#sprites.MEGA_KEYS)]
    local col = sprites.MEGA_COLORS[math.random(#sprites.MEGA_COLORS)]

    local function drawAt(char, slotX)
        local iw = sprites.megaWidth(char)
        local cx = slotX + math.max(0, math.floor((ICON_SLOT_W - iw) / 2))
        sprites.drawMega(gpu, char, cx, area.y, col, ui.COLOR.DESKTOP_BG)
    end
    drawAt(c1, area.x)
    drawAt(c2, area.x + ICON_SLOT_W + ICON_GAP)
    drawAt(c3, area.x + (ICON_SLOT_W + ICON_GAP) * 2)

    -- Заставка не проходит через ui.waitTouch (главный цикл ждёт событие
    -- "player_on" напрямую через event.pull), поэтому буфер нужно переносить
    -- на экран явно - иначе на GPU с двойной буферизацией анимация просто
    -- не будет видна.
    ui.flip()
end

return screensaver