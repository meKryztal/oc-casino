-- main.lua
-- Главная программа станции. Один экземпляр = один компьютер = один PIM + один монитор.
-- Можно поставить сколько угодно таких станций (2-4 и больше) - баланс всегда берётся
-- с банк-сервера по нику игрока, поэтому неважно, на какую станцию он встал.

local component = require("component")
local event = require("event")

local config      = require("config")
local net         = require("netlib")
local ui          = require("ui")
local games       = require("games")
local topup       = require("topup")
local screensaver = require("screensaver")

-- ===== Какой компонент у вас хранилище (см. probe.lua, если "me_interface" не подходит) =====
local STORAGE_COMPONENT = "me_interface"

local pim = component.pim
if not pim then
    error("PIM не найден на этой станции! Проверьте подключение.")
end

local storage = component.isAvailable(STORAGE_COMPONENT) and component[STORAGE_COMPONENT] or nil
if not storage then
    print("[warn] Компонент хранилища '" .. STORAGE_COMPONENT .. "' не найден.")
    print("[warn] Пополнение будет работать, вывод/выигрыши - нет, пока не поправите STORAGE_COMPONENT.")
end

-- Экран станции - берём первый доступный, если только один подключён к этому компьютеру.
local screenAddr = component.isAvailable("screen") and component.screen.address or nil
if not screenAddr then
    error("Монитор не найден на этой станции!")
end
ui.bind(screenAddr)

-- ===== Поиск банк-сервера =====
local bankAddr = nil
local function ensureBank()
    while not bankAddr do
        ui.clear(ui.COLOR.DESKTOP_BG)
        ui.centerText(math.floor(ui.H / 2), "Поиск банк-сервера...", ui.COLOR.TEXT_LIGHT)
        ui.flip() -- net.discoverBank ждёт через event.pull напрямую, минуя ui.waitTouch
        bankAddr = net.discoverBank(5)
    end
end
ensureBank()

local ICONS = {
    { id = "slots",    label = "Слоты" },
    { id = "dice",     label = "Кости" },
    { id = "deposit",  label = "Пополнение" },
    { id = "withdraw", label = "Вывод" },
}

local function fetchBalance(nick)
    local ok, result = net.call(bankAddr, { action = "get_balance", nick = nick })
    if ok then return result.chips, result.credits end
    -- банк временно недоступен - переоткрываем поиск и пробуем снова
    bankAddr = nil
    ensureBank()
    return fetchBalance(nick)
end

-- Один сеанс игрока: авторизован, стоит на PIM, видит рабочий стол, пока не сойдёт.
--
-- ВАЖНО: рабочий стол перерисовывается ТОЛЬКО когда это реально нужно (первый
-- вход, после закрытия игры/кассы, либо по таймауту ожидания - тогда баланс
-- мог измениться на другой станции). Раньше ui.desktop() (полная перерисовка
-- экрана + сетевой запрос баланса) вызывался на КАЖДОЙ итерации цикла, в том
-- числе когда игрок просто ткнул в пустое место мимо иконок - отсюда и
-- заметное мигание экрана при клике не по кнопке.
local function runSession(nick)
    ui.session.nick = nick
    ui.session.left = false

    local needsRedraw = true
    local hitboxes = {}
    local chips, credits = 0, 0

    while not ui.session.left do
        if needsRedraw then
            chips, credits = fetchBalance(nick)
            hitboxes = ui.desktop(nick, chips, credits, ICONS)
            needsRedraw = false
        end

        local tx, ty = ui.waitTouch(120)
        if ui.session.left then break end
        if not tx then
            -- Долгое бездействие - планово обновляем рабочий стол
            -- (баланс мог измениться на другой станции).
            needsRedraw = true
        else
            local chosenId = nil
            for _, hb in ipairs(hitboxes) do
                if ui.hit(hb.box, tx, ty) then chosenId = hb.id break end
            end

            if chosenId == "slots" then
                games.slots(ui, net, bankAddr, nick, "chips", config.WALLETS.chips.label, chips)
                needsRedraw = true
            elseif chosenId == "dice" then
                games.dice(ui, net, bankAddr, nick, "chips", config.WALLETS.chips.label, chips)
                needsRedraw = true
            elseif chosenId == "deposit" then
                topup.deposit(ui, net, bankAddr, pim, storage, nick)
                needsRedraw = true
            elseif chosenId == "withdraw" then
                topup.withdraw(ui, net, bankAddr, pim, storage, nick, { chips = chips, credits = credits })
                needsRedraw = true
            end
            -- chosenId == nil (клик мимо всех иконок) - НЕ перерисовываем,
            -- просто ждём следующее касание на том же экране без мигания.
        end
    end

    ui.session.nick = nil
end

-- ===== Главный цикл станции: ждём, пока кто-то встанет на PIM =====
-- Вместо статичной надписи "Добро пожаловать" - анимированная заставка
-- (screensaver.lua, на основе 2.lua). Фон рисуется один раз при входе в
-- режим ожидания (screensaver.start), а дальше каждые screensaver.FRAME_DELAY
-- секунд обновляются только сами символы (screensaver.update) - без полной
-- перерисовки экрана.
screensaver.start(ui)
while true do
    local ev, nick = event.pull(screensaver.FRAME_DELAY, "player_on")
    if ev and nick then
        local ok, err = pcall(runSession, nick)
        if not ok then
            print("[main] Ошибка в сессии игрока " .. tostring(nick) .. ": " .. tostring(err))
            -- раньше игрока просто молча кидало на "Добро пожаловать" без объяснений -
            -- теперь хотя бы покажем, что случилось, перед сбросом на заставку
            pcall(function()
                ui.messageBox("Сессия прервана", {
                    "Произошла ошибка, сессия закрыта.",
                    tostring(err):sub(1, 46),
                    "Сообщите администратору, если повторится.",
                }, 8)
            end)
        end
        screensaver.start(ui)
    else
        -- Таймаут (никто не встал) - обновляем только символы, отсюда анимация.
        screensaver.update(ui)
    end
end
