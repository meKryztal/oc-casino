-- bank_server.lua
-- Ставится на ОТДЕЛЬНЫЙ компьютер в серверной стойке (без экрана и PIM, только Network Card).
-- Хранит балансы ВСЕХ игроков в файлах на диске. Все станции стучатся сюда за
-- балансом/ставками - поэтому не важно, на какой PIM встал игрок, баланс всегда один.

package.loaded.config = nil
package.loaded.netlib = nil
local config = require("config")
local net    = require("netlib")
local serialization = require("serialization")
local filesystem = require("filesystem")

local DATA_DIR = "/home/casino_data/players/"
if not filesystem.exists(DATA_DIR) then
    filesystem.makeDirectory(DATA_DIR)
end

-- ===================== Хранилище =====================

local cache = {} -- nick -> {chips=n, credits=n}  (кэш в памяти + запись на диск при каждом изменении)

local function sanitize(nick)
    -- защита от "../" и прочего мусора в имени файла
    return (tostring(nick):gsub("[^%w_%-]", "_"))
end

local function pathFor(nick)
    return DATA_DIR .. sanitize(nick) .. ".dat"
end

local function loadPlayer(nick)
    if cache[nick] then return cache[nick] end
    local path = pathFor(nick)
    local data = { chips = 0, credits = 0 }
    if filesystem.exists(path) then
        local f = io.open(path, "r")
        if f then
            local raw = f:read("*a")
            f:close()
            local ok, parsed = pcall(serialization.unserialize, raw)
            if ok and type(parsed) == "table" then
                data.chips   = parsed.chips or 0
                data.credits = parsed.credits or 0
            end
        end
    end
    cache[nick] = data
    return data
end

local function savePlayer(nick)
    local data = cache[nick]
    if not data then return end
    local f = io.open(pathFor(nick), "w")
    if f then
        f:write(serialization.serialize(data))
        f:close()
    end
end

-- ===================== Обработчики запросов =====================

local handlers = {}

handlers.get_balance = function(req)
    local p = loadPlayer(req.nick)
    return true, { chips = p.chips, credits = p.credits }
end

-- Пополнение (после того как станция физически забрала ресурсы/валюту у игрока)
handlers.deposit = function(req)
    if type(req.amount) ~= "number" or req.amount <= 0 then
        return false, "bad_amount"
    end
    local wallet = req.wallet
    if wallet ~= "chips" and wallet ~= "credits" then
        return false, "bad_wallet"
    end
    local p = loadPlayer(req.nick)
    p[wallet] = p[wallet] + req.amount
    savePlayer(req.nick)
    return true, { balance = p[wallet] }
end

-- Резервирование средств под вывод. Если физическая выдача на станции не удалась,
-- станция ОБЯЗАНА вызвать refund с тем же amount, иначе игрок потеряет баланс.
handlers.withdraw = function(req)
    if type(req.amount) ~= "number" or req.amount <= 0 then
        return false, "bad_amount"
    end
    local wallet = req.wallet
    if wallet ~= "chips" and wallet ~= "credits" then
        return false, "bad_wallet"
    end
    local p = loadPlayer(req.nick)
    if p[wallet] < req.amount then
        return false, "insufficient_funds"
    end
    p[wallet] = p[wallet] - req.amount
    savePlayer(req.nick)
    return true, { balance = p[wallet] }
end

handlers.refund = function(req)
    -- используется станцией, если withdraw прошёл, а физически выдать предметы не получилось
    if type(req.amount) ~= "number" or req.amount <= 0 then
        return false, "bad_amount"
    end
    local wallet = req.wallet
    if wallet ~= "chips" and wallet ~= "credits" then
        return false, "bad_wallet"
    end
    local p = loadPlayer(req.nick)
    p[wallet] = p[wallet] + req.amount
    savePlayer(req.nick)
    return true, { balance = p[wallet] }
end

-- Атомарная ставка+результат: снимает bet, начисляет win (win=0 если проигрыш).
-- Держит игру "честной" по отношению к балансу - если игрок отключится/сгорит станция
-- посреди раунда, баланс всё равно останется консистентным, т.к. это один RPC-вызов.
handlers.settle_bet = function(req)
    local wallet = req.wallet
    if wallet ~= "chips" and wallet ~= "credits" then
        return false, "bad_wallet"
    end
    if type(req.bet) ~= "number" or req.bet < config.MIN_BET or req.bet > config.MAX_BET then
        return false, "bad_bet"
    end
    if type(req.win) ~= "number" or req.win < 0 then
        return false, "bad_win"
    end
    local p = loadPlayer(req.nick)
    if p[wallet] < req.bet then
        return false, "insufficient_funds"
    end
    p[wallet] = p[wallet] - req.bet + req.win
    savePlayer(req.nick)
    return true, { balance = p[wallet] }
end

-- ===================== Запуск с автоперезапуском =====================

print("=== Банк-сервер казино ===")
print("Данные игроков: " .. DATA_DIR)

while true do
    local ok, err = pcall(net.serve, handlers)
    if not ok then
        print("[bank_server] Ошибка, перезапуск через 2 сек: " .. tostring(err))
        os.sleep(2)
    end
end
