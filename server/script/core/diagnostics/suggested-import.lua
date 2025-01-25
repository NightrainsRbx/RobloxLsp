local files   = require 'files'
local vm      = require 'vm'
local lang    = require 'language'
local config  = require 'config'
local guide   = require 'core.guide'
local rbximports = require 'core.module-import'
local rbxlibs = require 'library.rbxlibs'

local function checkGlobal(src, uri, callback)
    local key = guide.getKeyName(src)
    if not key then
        return
    end
    local globals = vm.getGlobalSets(key, uri)
    for i = 1, #globals do
        if globals[i] == src then
            globals[i] = globals[#globals]
            globals[#globals] = nil
        end
    end
    if #globals == 0 and rbximports.hasPotentialImports(uri, key) then
        callback {
            start   = src.start,
            finish  = src.finish,
            message = lang.script('DIAG_SUGGESTED_IMPORT', key),
        }
        return
    end
end

local function checkType(src, uri, callback)
    if src[1] == "" then
        return
    end
    if src.typeAlias then
        return
    end
    if src.typeAliasGeneric then
        return
    end
    if src.parent.type == "type.module" then
        return
    end
    if rbxlibs.object[src[1]] then
        return
    end
    if rbximports.hasPotentialImports(uri, src[1]) then
        callback {
            start   = src.start,
            finish  = src.start + #src[1] - 1,
            message = lang.script('DIAG_SUGGESTED_IMPORT', src[1]),
        }
        return
    end
end

return function (uri, callback)
    if not config.config.suggestedImports.enable then
        return
    end

    local ast = files.getAst(uri)
    if not ast then
        return
    end

    guide.eachSourceType(ast.ast, 'getglobal', function (src)
        checkGlobal(src, uri, callback)
    end)

    guide.eachSourceType(ast.ast, 'setglobal', function (src)
        if guide.getParentFunction(src) ~= guide.getRoot(src) then
            checkGlobal(src, uri, callback)
        end
    end)

    guide.eachSourceType(ast.ast, 'type.name', function (src)
        checkType(src, uri, callback)
    end)
end
