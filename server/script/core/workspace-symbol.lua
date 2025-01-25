local files    = require 'files'
local guide    = require 'core.guide'
local matchKey = require 'core.match-key'
local define   = require 'proto.define'
local await    = require 'await'
local workspace = require 'workspace'

local function buildSource(uri, source, key, results)
    if source.dummy then
        return
    end
    if     source.type == 'local'
    or     source.type == 'setlocal'
    or     source.type == 'setglobal' then
        local name = source[1]
        if matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Variable,
                uri   = uri,
                range = { source.start, source.finish },
            }
        end
    elseif source.type == 'setfield'
    or     source.type == 'tablefield' then
        local field = source.field
        local name  = field and field[1]
        if name and matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Field,
                uri   = uri,
                range = { field.start, field.finish },
            }
        end
    elseif source.type == 'setmethod' then
        local method = source.method
        local name   = method and method[1]
        if name and matchKey(key, name) then
            results[#results+1] = {
                name  = name,
                kind  = define.SymbolKind.Method,
                uri   = uri,
                range = { method.start, method.finish },
            }
        end
    end
end

local function searchFile(uri, key, results)
    local ast = files.getAst(uri)
    if not ast then
        return
    end

    guide.eachSource(ast.ast, function (source)
        buildSource(uri, source, key, results)
    end)
end

return function (key)
    local results = {}

    for uri in files.eachFile() do
        if not workspace.isIgnored(uri) then
            searchFile(files.getOriginUri(uri), key, results)
            if #results > 1000 then
                break
            end
            await.delay()
        end
    end

    return results
end
