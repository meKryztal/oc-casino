-- main.lua
-- Главная программа станции. Один экземпляр = один компьютер = один PIM + один монитор.
-- Можно поставить сколько угодно таких станций (2-4 и больше) - баланс всегда берётся
-- с банк-сервера по нику игрока, поэтому неважно, на какую станцию он встал.

local component = require("component")
local event = require("event")

local config = require("config")
local net    = require("netlib")
local ui     = require("ui")
local games  = require("games")
local topup  = require("topup")

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
        bankAddr = net.discoverBank(5)
    end
end
ensureBank()

local ICONS = {
    { id = "slots",    label = "Слоты" },
    { id = "dice",     label = "Кости" },
    { id = "coinflip", label = "Монетка" },
    { id = "deposit",  label = "Касса: внести" },
    { id = "withdraw", label = "Касса: вывод" },
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
local function runSession(nick)
    ui.session.nick = nick
    ui.session.left = false

    while not ui.session.left do
        local chips, credits = fetchBalance(nick)
        local hitboxes = ui.desktop(nick, chips, credits, ICONS)

        local tx, ty = ui.waitTouch(120)
        if ui.session.left then break end
        if not tx then
            -- долгое бездействие - просто перерисуем рабочий стол (баланс мог измениться на другой станции)
        else
            local chosenId = nil
            for _, hb in ipairs(hitboxes) do
                if ui.hit(hb.box, tx, ty) then chosenId = hb.id break end
            end

            if chosenId == "slots" then
                games.slots(ui, net, bankAddr, nick, "chips", config.WALLETS.chips.label, chips)
            elseif chosenId == "dice" then
                games.dice(ui, net, bankAddr, nick, "chips", config.WALLETS.chips.label, chips)
            elseif chosenId == "coinflip" then
                games.coinflip(ui, net, bankAddr, nick, "chips", config.WALLETS.chips.label, chips)
            elseif chosenId == "deposit" then
                topup.deposit(ui, net, bankAddr, pim, storage, nick)
            elseif chosenId == "withdraw" then
                topup.withdraw(ui, net, bankAddr, pim, storage, nick, { chips = chips, credits = credits })
            end
        end
    end

    ui.session.nick = nil
    ui.clear(ui.COLOR.DESKTOP_BG)
    ui.centerText(math.floor(ui.H / 2), "До встречи, " .. nick .. "!", ui.COLOR.TEXT_LIGHT)
    os.sleep(1.5)
end

-- ===== Главный цикл станции: ждём, пока кто-то встанет на PIM =====
local function idleScreen()
    ui.clear(ui.COLOR.DESKTOP_BG)
    local w, h = math.min(ui.W - 4, 50), 9
    local x = math.floor((ui.W - w) / 2)
    local y = math.floor((ui.H - h) / 2)
    ui.drawBorder(x, y, w, h, ui.COLOR.ACCENT_GOLD)
    ui.centerText(y + 2, "\u{2666}\u{2666}\u{2666}  К А З И Н О  \u{2666}\u{2666}\u{2666}", ui.COLOR.ACCENT_GOLD)
    ui.centerText(y + 4, "Добро пожаловать!", ui.COLOR.TEXT_LIGHT)
    ui.centerText(y + 6, "Встаньте на плиту для авторизации", ui.COLOR.TEXT_MUTED)
end

idleScreen()
while true do
    local ev, nick = event.pull(2, "player_on")
    if ev and nick then
        local ok, err = pcall(runSession, nick)
        if not ok then
            print("[main] Ошибка в сессии игрока " .. tostring(nick) .. ": " .. tostring(err))
            -- раньше игрока просто молча кидало на "Добро пожаловать" без объяснений -
            -- теперь хотя бы покажем, что случилось, перед сбросом на idleScreen()
            pcall(function()
                ui.messageBox("Сессия прервана", {
                    "Произошла ошибка, сессия закрыта.",
                    tostring(err):sub(1, 46),
                    "Сообщите администратору, если повторится.",
                }, 8)
            end)
        end
        idleScreen()
    end
end
