local files          = require 'files'
local guide          = require 'core.guide'
local await          = require 'await'
local define         = require 'proto.define'
local vm             = require 'vm'
local defaultlibs    = require 'library.defaultlibs'

local Care = {}
Care['setglobal'] = function (source, results)
    local isLib = vm.isGlobalLibraryName(source[1])
    if not isLib then
        results[#results+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = define.TokenTypes.namespace,
            modifiers  = define.TokenModifiers.deprecated,
        }
    end
end
Care['getglobal'] = function (source, results)
    local isLib = vm.isGlobalLibraryName(source[1])
    if not isLib then
        results[#results+1] =  {
            start      = source.start,
            finish     = source.finish,
            type       = define.TokenTypes.namespace,
            modifiers  = define.TokenModifiers.deprecated,
        }
    end
end
Care['tablefield'] = function (source, results)
    local field = source.field
    if not field then
        return
    end
    results[#results+1] = {
        start      = field.start,
        finish     = field.finish,
        type       = define.TokenTypes.property,
        modifiers  = define.TokenModifiers.declaration,
    }
end
Care['getlocal'] = function (source, results)
    if source.parent.type == "type.module" then
        results[#results+1] = {
            start     = source.start,
            finish    = source.finish,
            type      = define.TokenTypes.type,
        }
        return
    end

    local loc = source.node
    -- 1. 值为函数的局部变量
    local hasFunc
    local node = loc.node
    if node then
        for _, ref in ipairs(node.ref) do
            local def = ref.value
            if def.type == 'function' then
                hasFunc = true
                break
            end
        end
    end
    if hasFunc then
        results[#results+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = define.TokenTypes.interface,
            modifiers  = define.TokenModifiers.declaration,
        }
        return
    end
    -- 2. 对象
    if  source.parent.type == 'getmethod'
    and source.parent.node == source then
        return
    end
    -- 3. 特殊变量
    if source[1] == '_ENV'
    or source[1] == 'self' then
        return
    end
    -- 4. 函数的参数

    -- 6. 函数调用
    if  source.parent.type == 'call'
    and source.parent.node == source then
        return
    end
    local parent = loc.parent
    if not parent then
        return
    end
    if parent.type == "in" and parent.keys then
        for i, key in ipairs(parent.keys) do
            if key == loc then
                break
            elseif i == #parent.keys then
                return
            end
        end
    elseif parent.type == "loop" then
        if parent.loc ~= loc then
            return
        end
    elseif parent.type ~= "funcargs" then
        return
    end
    results[#results+1] = {
        start      = source.start,
        finish     = source.finish,
        type       = define.TokenTypes.parameter,
        modifiers  = define.TokenModifiers.declaration,
    }
end
Care['setlocal'] = Care['getlocal']
Care['doc.return.name'] = function (source, results)
    results[#results+1] = {
        start  = source.start,
        finish = source.finish,
        type   = define.TokenTypes.parameter,
    }
end
Care['doc.tailcomment'] = function (source, results)
    results[#results+1] = {
        start  = source.start,
        finish = source.finish,
        type   = define.TokenTypes.comment,
    }
end
Care['doc.type.name'] = function (source, results)
    if source.typeGeneric then
        results[#results+1] = {
            start  = source.start,
            finish = source.finish,
            type   = define.TokenTypes.macro,
        }
    end
end
Care['type.name'] = function (source, results)
    if source[1] == "" or source[1]:match("%.$") then
        return
    end
    if source[1]:match("%.") then
        results[#results+1] = {
            start  = source.start,
            finish = source.start + #source[1]:match("^(%w+)") - 1,
            type   = define.TokenTypes.type,
        }
        results[#results+1] = {
            start  = source.nameStart,
            finish = source.nameStart + #source[1]:match("(%w+)$") - 1,
            type   = define.TokenTypes.type,
        }
    else
        local result = {
            start  = source.start,
            finish = source.start + #source[1] - 1,
            type   = define.TokenTypes.type,
        }
        if source.typeAliasGeneric then
            result.type = define.TokenTypes.typeParameter
        elseif defaultlibs.primitiveTypes[source[1]] then
            result.modifiers = define.TokenModifiers.primitive
        end
        results[#results+1] = result
    end
end
Care['type.parameter'] = function (source, results)
    results[#results+1] = {
        start  = source.start,
        finish = source.finish,
        type   = define.TokenTypes.typeParameter,
    }
end
Care['type.field.key'] = function (source, results)
    results[#results+1] = {
        start     = source.start,
        finish    = source.finish,
        type      = define.TokenTypes.property,
        modifiers = define.TokenModifiers.declaration
    }
    if source.parent.readOnly then
        results[#results].modifiers = define.TokenModifiers.readonly
    end
end
Care['type.typeof'] = function (source, results)
    results[#results+1] = {
        start  = source.name.start,
        finish = source.name.finish,
        type   = define.TokenTypes["function"]
    }
end
Care['call'] = function (source, results)
    if not source.node or source.nocheck then
        return
    end
    if source.node.type == "getlocal"
    or source.node.type == "getfield"
    or source.node.type == "getmethod" then
        local node = source.node.field or source.node.method or source.node
        results[#results+1] = {
            start  = node.start,
            finish = node.finish,
            type   = define.TokenTypes["function"]
        }
    end
end

local function buildTokens(uri, results)
    local tokens = {}
    local lastLine = 0
    local lastStartChar = 0
    for i, source in ipairs(results) do
        local startPos  = files.position(uri, source.start)
        local finishPos = files.position(uri, source.finish)
        local line      = startPos.line
        local startChar = startPos.character - 1
        local deltaLine = line - lastLine
        local deltaStartChar
        if deltaLine == 0 then
            deltaStartChar = startChar - lastStartChar
        else
            deltaStartChar = startChar
        end
        lastLine = line
        lastStartChar = startChar
        -- see https://microsoft.github.io/language-server-protocol/specifications/specification-3-16/#textDocument_semanticTokens
        local len = i * 5 - 5
        tokens[len + 1] = deltaLine
        tokens[len + 2] = deltaStartChar
        tokens[len + 3] = finishPos.character - startPos.character + 1 -- length
        tokens[len + 4] = source.type
        tokens[len + 5] = source.modifiers or 0
    end
    return tokens
end

return function (uri, start, finish)
    local ast   = files.getAst(uri)
    local lines = files.getLines(uri)
    local text  = files.getText(uri)
    if not ast then
        return nil
    end

    local results = {}
    local count = 0
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        local method = Care[source.type]
        if not method then
            return
        end
        method(source, results)
        count = count + 1
        if count % 100 == 0 then
            await.delay()
        end
    end)

    table.sort(results, function (a, b)
        return a.start < b.start
    end)

    local tokens = buildTokens(uri, results)

    return tokens
end
