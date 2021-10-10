---@type vm
local vm      = require 'vm.vm'
local files   = require 'files'
local ws      = require 'workspace'
local guide   = require 'core.guide'
local await   = require 'await'
local config  = require 'config'
local rojo    = require 'library.rojo'
local fs      = require 'bee.filesystem'
local furi    = require 'file-uri'

local m = {}

function m.searchFileReturn(results, ast, index)
    local returns = ast.returns
    if not returns then
        return
    end
    for _, ret in ipairs(returns) do
        local exp = ret[index]
        if exp then
            vm.mergeResults(results, { exp })
        end
    end
end

function m.require(status, args, index)
    local reqScript = args and args[1]
    if not reqScript then
        return nil
    end
    local results = {}
    local newStatus = guide.status(status)
    guide.searchRefs(newStatus, reqScript, "def")
    for _, def in ipairs(newStatus.results) do
        if def.uri then
            local lib = rojo:matchLibrary(def.uri)
            if lib then
                return {lib}
            end
            if not files.eq(guide.getUri(args[1]), def.uri) then
                if not files.exists(def.uri) then
                    ws.load(def.uri)
                end
                local ast = files.getAst(def.uri)
                if ast then
                    m.searchFileReturn(results, ast.ast, index)
                    break
                end
            end
        end
    end
    return results
end

vm.interface = {}

-- 向前寻找引用的层数限制，一般情况下都为0
-- 在自动完成/漂浮提示等情况时设置为5（需要清空缓存）
-- 在查找引用时设置为10（需要清空缓存）
vm.interface.searchLevel = 0

function vm.interface.call(status, func, args, index)
    if func.special == 'require' and index == 1 then
        await.delay()
        return m.require(status, args, index)
    end
end

function vm.interface.module(obj)
    local results = {}
    local myUri = guide.getUri(obj)
    local uris = ws.findUrisByRequirePath(obj.path)
    if #uris == 0 then
        local input = obj.path:gsub('%.', '/'):gsub('%%', '%%%%')
        for _, luapath in ipairs(config.config.runtime.path) do
            local path = fs.path(ws.normalize(luapath:gsub('%?', input)))
            if fs.exists(path) then
                local uri = furi.encode(fs.absolute(path):string())
                if uri then
                    ws.load(uri)
                    uris[#uris+1] = uri
                end
                break
            end
        end
    end
    for _, uri in ipairs(uris) do
        if not files.eq(myUri, uri) then
            local ast = files.getAst(uri)
            if ast then
                m.searchFileReturn(results, ast.ast, 1)
            end
        end
    end
    return results
end

function vm.interface.global(name, onlyDef, uri)
    await.delay()
    if onlyDef then
        return vm.getGlobalSets(name, uri)
    else
        return vm.getGlobals(name, uri)
    end
end

function vm.interface.docType(name)
    await.delay()
    return vm.getDocTypes(name)
end

function vm.interface.link(reqUri)
    await.delay()
    local links = {}
    local requires = files.getRequiring(reqUri)
    for _, uri in ipairs(requires) do
        links[#links+1] = requires[uri]
    end
    return links
end

function vm.interface.cache(options)
    await.delay()
    return vm.getCache('cache', options)
end

function vm.interface.getSearchDepth()
    return config.config.intelliSense.searchDepth
end

function vm.interface.pulse()
    await.delay()
end
