<<<<<<< HEAD
local fs        = require 'bee.filesystem'
local rpc       = require 'rpc'
local config    = require 'config'
local glob      = require 'glob'
local platform  = require 'bee.platform'
local sandbox   = require 'sandbox'

local Plugins

local function showError(msg)
    local traceback = log.error(msg)
    rpc:notify('window/showMessage', {
        type = 3,
        message = traceback,
    })
    return traceback
end

local function showWarn(msg)
    log.warn(msg)
    rpc:notify('window/showMessage', {
        type = 3,
        message = msg,
    })
    return msg
end

local function scan(path, callback)
    if fs.is_directory(path) then
        for p in path:list_directory() do
            scan(p, callback)
        end
    else
        callback(path)
    end
end

local function loadPluginFrom(path, root)
    log.info('Load plugin from:', path:string())
    local env = setmetatable({}, { __index = _G })
    sandbox(path:filename():string(), root:string(), io.open, package.loaded, env)
    Plugins[#Plugins+1] = env
end

local function load(workspace)
    Plugins = nil

    if not config.config.plugin.enable then
        return
    end
    local suc, path = xpcall(fs.path, showWarn, config.config.plugin.path)
    if not suc then
        return
    end

    Plugins = {}
    local pluginPath
    if workspace then
        pluginPath = fs.absolute(workspace.root / path)
    else
        pluginPath = fs.absolute(path)
    end
    if not fs.is_directory(pluginPath) then
        pluginPath = pluginPath:parent_path()
    end

    local pattern = {config.config.plugin.path}
    local options = {
        ignoreCase = platform.OS == 'Windows'
    }
    local parser = glob.glob(pattern, options)

    scan(pluginPath:parent_path(), function (filePath)
        if parser(filePath:string()) then
            loadPluginFrom(filePath, pluginPath)
        end
    end)
end

local function call(name, ...)
    if not Plugins then
        return nil
    end
    for _, plugin in ipairs(Plugins) do
        if type(plugin[name]) == 'function' then
            local suc, res = xpcall(plugin[name], showError, ...)
            if suc and res ~= nil then
                return res
            end
        end
    end
    return nil
end

return {
    load = load,
    call = call,
}
=======
local config = require 'config'
local fs     = require 'bee.filesystem'
local fsu    = require 'fs-utility'
local await  = require "await"

---@class plugin
local m = {}
m.waitingReady = {}

function m.dispatch(event, ...)
    if not m.interface then
        return false
    end
    local method = m.interface[event]
    if type(method) ~= 'function' then
        return false
    end
    tracy.ZoneBeginN('plugin dispatch:' .. event)
    local suc, res1, res2 = xpcall(method, log.error, ...)
    tracy.ZoneEnd()
    if suc then
        return true, res1, res2
    end
    return false, res1
end

function m.isReady()
    return m.interface ~= nil
end

function m.awaitReady()
    if m.isReady() then
        return
    end
    await.wait(function (waker)
        m.waitingReady[#m.waitingReady+1] = waker
    end)
end

function m.init()
    local ws    = require 'workspace'
    m.interface = {}

    local _ <close> = function ()
        local waiting = m.waitingReady
        m.waitingReady = {}
        for _, waker in ipairs(waiting) do
            waker()
        end
    end

    local pluginPath = fs.path(config.config.runtime.plugin)
    if pluginPath:is_relative() then
        if not ws.path then
            return
        end
        pluginPath = fs.path(ws.path) / pluginPath
    end
    local pluginLua = fsu.loadFile(pluginPath)
    if not pluginLua then
        return
    end
    local env = setmetatable(m.interface, { __index = _ENV })
    local f, err = load(pluginLua, '@'..pluginPath:string(), "t", env)
    if not f then
        log.error(err)
        return
    end
    xpcall(f, log.error, f)
end

return m
>>>>>>> origin/master
