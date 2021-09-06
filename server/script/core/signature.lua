<<<<<<< HEAD
local getFunctionHover = require 'core.hover.function'
local getFunctionHoverAsLib = require 'core.hover.lib_function'
local getFunctionHoverAsEmmy = require 'core.hover.emmy_function'
local findLib = require 'core.find_lib'
local buildValueName = require 'core.hover.name'
local findSource = require 'core.find_source'

local function findCall(vm, pos)
    local results = {}
    vm:eachSource(function (src)
        if      src.type == 'call'
            and src.start <= pos
            and src.finish >= pos
        then
            results[#results+1] = src
        end
    end)
    if #results == 0 then
        return nil
    end
    -- 可能处于 'func1(func2(' 的嵌套中，将最近的call放到最前面
    table.sort(results, function (a, b)
        return a.start > b.start
    end)
    return results
end

local function getSelect(args, pos)
    if not args then
        return 1
    end
    for i, arg in ipairs(args) do
        if arg.start <= pos and arg.finish >= pos - 1 then
            return i
        end
    end
    return #args + 1
end

local function getFunctionSource(call)
    local simple = call:get 'simple'
    for i, source in ipairs(simple) do
        if source == call then
            return simple[i-1]
        end
    end
    return nil
end

local function getHover(call, pos)
    local args = call:bindCall()
    if not args then
        return nil
    end

    local value = call:findCallFunction()
    if not value then
        return nil
    end

    local select = getSelect(args, pos)
    local source = getFunctionSource(call)
    local object = source:get 'object'
    local lib, fullkey = findLib(source)
    local name = fullkey or buildValueName(source)
    local hover
    if lib then
        hover = getFunctionHoverAsLib(name, lib, object, select, true)
    else
        local emmy = value:getEmmy()
        if emmy and emmy.type == 'emmy.functionType' then
            hover = {getFunctionHoverAsEmmy(name, emmy, object, select)}
        else
            ---@type emmyFunction
            local func = value:getFunction()
            hover = {getFunctionHover(name, func, object, select)}
            local overLoads = func and func:getEmmyOverLoads()
            if overLoads then
                for _, ol in ipairs(overLoads) do
                    hover = {getFunctionHoverAsEmmy(name, ol, object, select)}
                end
            end
        end
    end
    return hover
end

local function isInFunctionOrTable(call, pos)
    local args = call:bindCall()
    if not args then
        return false
    end
    local select = getSelect(args, pos)
    local arg = args[select]
    if not arg then
        return false
    end
    if arg.type == 'function' or arg.type == 'table' then
=======
local files      = require 'files'
local guide      = require 'core.guide'
local vm         = require 'vm'
local hoverLabel = require 'core.hover.label'
local hoverDesc  = require 'core.hover.description'

local function findNearCall(uri, ast, pos)
    local text = files.getText(uri)
    local nearCall
    guide.eachSourceContain(ast.ast, pos, function (src)
        if src.type == 'call'
        or src.type == 'table'
        or src.type == 'function' then
            -- call(),$
            if  src.finish <= pos
            and text:sub(src.finish, src.finish) == ')' then
                return
            end
            -- {},$
            if  src.finish <= pos
            and text:sub(src.finish, src.finish) == '}' then
                return
            end
            if not nearCall or nearCall.start <= src.start then
                nearCall = src
            end
        end
    end)
    if not nearCall then
        return nil
    end
    if nearCall.type ~= 'call' then
        return nil
    end
    return nearCall
end

local function countFuncArgs(source)
    local result = 0
    if not source.args or #source.args == 0 then
        return result
    end
    local lastArg = source.args[#source.args]
    if lastArg.type == "type.variadic" then
        return math.maxinteger
    elseif source.args[#source.args].type == '...' then
        return math.maxinteger
    end
    result = result + #source.args
    return result
end

local function makeOneSignature(source, oop, index)
    local label = hoverLabel(source, oop)
    label = label:gsub('%s*\f%s*->.+', ''):gsub("\f", "")
    local argStart, argLabel = label:match("()(%b())$")
    argLabel = argLabel:sub(2, #argLabel - 1)
    for _, pattern in ipairs({"()", "{}", "[]", "<>"}) do
        argLabel = argLabel:gsub("%b" .. pattern, function(str)
            return ('_'):rep(#str)
        end)
    end
    local params = {}
    local i = 0
    for start, finish in argLabel:gmatch '%s*()[^,]+()' do
        i = i + 1
        params[i] = {
            label = {start + argStart, finish - 1 + argStart},
        }
    end
    if index > i and i > 0 then
        local lastLabel = params[i].label
        local text = label:sub(lastLabel[1], lastLabel[2])
        if text:sub(1, 3) == '...' then
            index = i
        end
    end
    return {
        label       = label,
        params      = params,
        index       = index,
        description = hoverDesc(source),
    }
end

local function eachFunctionAndOverload(value, callback)
    if value.type == "type.inter" then
        for _, obj in ipairs(guide.getAllValuesInType(value, "type.function")) do
            callback(obj)
        end
        return
    end
    callback(value)
    if value.bindDocs then
        for _, doc in ipairs(value.bindDocs) do
            if doc.type == 'doc.overload' then
                callback(doc.overload)
            end
        end
    end
    if value.overload then
        for _, overload in ipairs(value.overload) do
            callback(overload)
        end
    end
end

local function makeSignatures(call, pos)
    local node = call.node
    local oop = node.type == 'method'
             or node.type == 'getmethod'
             or node.type == 'setmethod'
    local index
    if call.args then
        local args = {}
        for _, arg in ipairs(call.args) do
            if not arg.dummy then
                args[#args+1] = arg
            end
        end
        for i, arg in ipairs(args) do
            if arg.start <= pos and arg.finish >= pos then
                index = i
                break
            end
        end
        if not index then
            index = #args + 1
        end
    else
        index = 1
    end
    local signs = {}
    local defs = vm.getDefs(node, 0, {onlyDef = true})
    local mark = {}
    for _, src in ipairs(defs) do
        src = guide.getObjectValue(src) or src
        if src.type == 'function'
        or src.type == 'doc.type.function'
        or src.type == 'type.function'
        or src.type == 'type.inter' then
            eachFunctionAndOverload(src, function(value)
                if not mark[value] then
                    mark[value] = true
                    if index == 1 or index <= countFuncArgs(value) then
                        signs[#signs+1] = makeOneSignature(value, oop, index)
                    end
                end
            end)
        end
    end
    return signs
end

local function isSpace(char)
    if char == ' '
    or char == '\n'
    or char == '\r'
    or char == '\t' then
>>>>>>> origin/master
        return true
    end
    return false
end

<<<<<<< HEAD
return function (vm, pos)
    local source = findSource(vm, pos) or findSource(vm, pos-1)
    if not source or source.type == 'string' then
        return
    end
    local calls = findCall(vm, pos)
    if not calls or #calls == 0 then
        return nil
    end

    local nearCall = calls[1]
    if isInFunctionOrTable(nearCall, pos) then
        return nil
    end

    local hovers = getHover(nearCall, pos)
    if not hovers then
        return nil
    end

    -- skip `name(`
    for _, hover in pairs(hovers) do
        local head = #hover.name + 1
        hover.label = ('%s(%s)'):format(hover.name, hover.argStr)
        if hover.argLabel then
            hover.argLabel[1] = hover.argLabel[1] + head
            hover.argLabel[2] = hover.argLabel[2] + head
        end
    end
    return hovers
=======
local function skipSpace(text, offset)
    for i = offset, 1, -1 do
        local char = text:sub(i, i)
        if not isSpace(char) then
            return i
        end
    end
    return 0
end

return function (uri, pos)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end
    local text = files.getText(uri)
    pos = skipSpace(text, pos)
    local call = findNearCall(uri, ast, pos)
    if not call then
        return nil
    end
    local signs = makeSignatures(call, pos)
    if not signs or #signs == 0 then
        return nil
    end
    return signs
>>>>>>> origin/master
end
