-- netlib.lua
-- Общая мини-RPC библиотека поверх сетевых карт OpenComputers.
-- Используется и банк-сервером (принимает запросы), и станциями (шлют запросы).

local component     = require("component")
local computer       = require("computer")
local event          = require("event")
local serialization  = require("serialization")

local config = require("config")

local net = {}

local modem = component.modem
if not modem then
    error("Не найдена сетевая карта (Network Card) на этом компьютере!")
end

modem.open(config.NET_PORT)

local function newId()
    return tostring(math.random(1, 2^30)) .. "-" .. tostring(computer and computer.uptime and computer.uptime() or os.time())
end

-- ===================== СТОРОНА СТАНЦИИ (клиент) =====================

-- Найти адрес банк-сервера широковещательным запросом.
-- Возвращает адрес или nil, если банк не ответил.
function net.discoverBank(timeout)
    timeout = timeout or config.NET_TIMEOUT
    modem.broadcast(config.NET_PORT, serialization.serialize({ type = "discover" }))

    local deadline = (computer.uptime()) + timeout
    while computer.uptime() < deadline do
        local ev, _, from, port, _, payload = event.pull(deadline - computer.uptime(), "modem_message")
        if ev and port == config.NET_PORT and payload then
            local ok, data = pcall(serialization.unserialize, payload)
            if ok and data and data.type == "discover_reply" then
                return from
            end
        end
    end
    return nil
end

-- Отправить запрос банку и дождаться ответа (с ретраями).
-- request: таблица, обязательно содержит поле "action".
-- Возвращает: ok(boolean), result(table-или-строка ошибки)
function net.call(bankAddress, request)
    local id = newId()
    request.id = id
    local payload = serialization.serialize(request)

    for attempt = 1, config.NET_RETRIES do
        modem.send(bankAddress, config.NET_PORT, payload)

        local deadline = computer.uptime() + config.NET_TIMEOUT
        while computer.uptime() < deadline do
            local ev, _, from, port, _, respPayload = event.pull(deadline - computer.uptime(), "modem_message")
            if ev and from == bankAddress and port == config.NET_PORT and respPayload then
                local ok, resp = pcall(serialization.unserialize, respPayload)
                if ok and resp and resp.id == id then
                    if resp.ok then
                        return true, resp.result
                    else
                        return false, resp.error or "unknown_error"
                    end
                end
                -- иначе - чужой/устаревший ответ, читаем дальше в рамках дедлайна
            end
        end
        -- таймаут - пробуем ещё раз (banком мог быть занят)
    end

    return false, "bank_timeout"
end

-- ===================== СТОРОНА БАНК-СЕРВЕРА =====================

-- Запустить сервер: handlers - таблица { [action] = function(reqTable) return okBoolean, resultOrError end }
-- Функция блокирующая, крутится вечно (используйте внутри pcall-цикла с автоперезапуском).
function net.serve(handlers, onLoopTick)
    print("[net] Банк-сервер слушает порт " .. config.NET_PORT .. " ...")
    while true do
        local ev, _, from, port, _, payload = event.pull(1, "modem_message")
        if ev and port == config.NET_PORT and payload then
            local ok, req = pcall(serialization.unserialize, payload)
            if ok and req then
                if req.type == "discover" then
                    modem.send(from, config.NET_PORT, serialization.serialize({ type = "discover_reply" }))
                elseif req.action then
                    local handler = handlers[req.action]
                    local respOk, result
                    if handler then
                        local callOk, a, b = pcall(handler, req)
                        if callOk then
                            respOk, result = a, b
                        else
                            respOk, result = false, tostring(a)
                        end
                    else
                        respOk, result = false, "unknown_action:" .. tostring(req.action)
                    end
                    modem.send(from, config.NET_PORT, serialization.serialize({
                        id = req.id, ok = respOk, result = respOk and result or nil, error = (not respOk) and result or nil,
                    }))
                end
            end
        end
        if onLoopTick then onLoopTick() end
    end
end

return net