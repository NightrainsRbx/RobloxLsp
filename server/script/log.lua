local rpc = require 'rpc'
local config = require 'config'

local log = {}

local prefix_len = #ROOT:string()

local function trim_src(src)
    src = src:sub(prefix_len + 3, -5)
    src = src:gsub('^[/\\]+', '')
    src = src:gsub('[\\/]+', '.')
    return src
end

--[[
    Minics how Roblox deals with many args by adding a space inbetween each arg.

    Examples:
    log.info('Hello', 'World') -> 'Hello World'
    log.info('Hello ', 'World') -> 'Hello  World' (Notice the 2 spaces.)
]]
local function HandleMessageArgs(level, ...)

    -- Pack all the args into a table
    local t = table.pack(...)

    -- Convert each to a string
    for i = 1, t.n do
        t[i] = tostring(t[i])
    end

    -- Gather where the message came from originally.
    local ScriptInfo = debug.getinfo(3, 'Sl')

    -- Combine everything into a message
    local str = '['..trim_src(ScriptInfo.source)..':'..ScriptInfo.currentline..'] '.. table.concat(t, ' ', 1, t.n)

    -- If the level is an error, attach the stack to the message.
    if level == 'error' then
        str = str..'\n'..debug.traceback(nil, 3)
    end

    return str
end

function log.info(...)
    rpc:notify('window/logMessage', {
        type = 3,
        message = HandleMessageArgs('info', ...)
    })

end

function log.debug(...)
    if config.config.logging.showDebugMessages then
        rpc:notify('window/logMessage', {
            type = 4,
            message = HandleMessageArgs('debug', ...)
        })
    end
end

function log.warn(...)
    rpc:notify('window/logMessage', {
        type = 2,
        message = HandleMessageArgs('warn', ...)
    })
end

function log.error(...)
    rpc:notify('window/logMessage', {
        type = 1,
        message = HandleMessageArgs('error', ...)
    })
end

function log.init(root, path)
    -- log.path = path:string()
    -- log.prefix_len = #root:string()
end

return log
