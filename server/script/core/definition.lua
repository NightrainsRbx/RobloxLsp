<<<<<<< HEAD
local findSource = require 'core.find_source'
local Mode

local function parseValueSimily(callback, vm, source)
    local key = source[1]
    if not key then
        return nil
    end
    vm:eachSource(function (other)
        if other == source then
            goto CONTINUE
        end
        if      other[1] == key
            and not other:bindLocal()
            and other:bindValue()
            and source:bindValue() ~= other:bindValue()
        then
            if Mode == 'definition' then
                if other:action() == 'set' then
                    callback(other)
                end
            elseif Mode == 'reference' then
                if other:action() == 'set' or other:action() == 'get' then
                    callback(other)
                end
            end
        end
        :: CONTINUE ::
    end)
end

local function parseLocal(callback, vm, source)
    ---@type Local
    local loc = source:bindLocal()
    callback(loc:getSource())
    loc:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' or info.type == 'local' then
                if vm.uri == src:getUri() then
                    if source.id >= src.id then
                        callback(src)
                    end
                end
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'local' or info.type == 'return' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function parseValueByValue(callback, vm, source, value)
    if not source then
        return
    end
    local mark = { [vm] = true }
    local list = {}
    for _ = 1, 5 do
        value:eachInfo(function (info, src)
            if Mode == 'definition' then
                if info.type == 'local' then
                    if vm.uri == src:getUri() then
                        if source.id >= src.id then
                            callback(src)
                        end
                    end
                end
                if info.type == 'set' then
                    if vm.uri == src:getUri() then
                        if source.id >= src.id then
                            callback(src)
                        end
                    else
                        callback(src)
                    end
                end
                if info.type == 'return' then
                    if (src.type ~= 'simple' or src[#src].type == 'call')
                    and src.type ~= 'name'
                    then
                        callback(src)
                    end
                    if vm.lsp then
                        local destVM = vm.lsp:getVM(src:getUri())
                        if destVM and not mark[destVM] then
                            mark[destVM] = true
                            list[#list+1] = { destVM, src }
                        end
                    end
                end
            elseif Mode == 'reference' then
                if info.type == 'set' or info.type == 'local' or info.type == 'return' or info.type == 'get' then
                    callback(src)
                end
            end
        end)
        local nextData = table.remove(list, 1)
        if nextData then
            vm, source = nextData[1], nextData[2]
        end
    end
end

local function parseValue(callback, vm, source)
    local value = source:bindValue()
    local isGlobal
    if value then
        isGlobal = value:isGlobal()
        parseValueByValue(callback, vm, source, value)
        local emmy = value:getEmmy()
        if emmy and emmy.type == 'emmy.type' then
            ---@type EmmyType
            local emmyType = emmy
            emmyType:eachClass(function (class)
                if class and class:getValue() then
                    local emmyVM = vm
                    if vm.lsp then
                        local destVM = vm.lsp:getVM(class:getSource():getUri())
                        if destVM then
                            emmyVM = destVM
                        end
                    end
                    parseValueByValue(callback, emmyVM, class:getValue():getSource(), class:getValue())
                end
            end)
        end
    end
    local parent = source:get 'parent'
    for _ = 1, 3 do
        if parent then
            local ok = parent:eachInfo(function (info, src)
                if Mode == 'definition' then
                    if info.type == 'set child' and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                elseif Mode == 'reference' then
                    if (info.type == 'set child' or info.type == 'get child') and info[1] == source[1] then
                        callback(src)
                        return true
                    end
                end
            end)
            if ok then
                break
            end
            parent = parent:getMetaMethod('__index')
        end
    end
    return isGlobal
end

local function parseLabel(callback, vm, label)
    label:eachInfo(function (info, src)
        if Mode == 'definition' then
            if info.type == 'set' then
                callback(src)
            end
        elseif Mode == 'reference' then
            if info.type == 'set' or info.type == 'get' then
                callback(src)
            end
        end
    end)
end

local function jumpUri(callback, vm, source)
    local uri = source:get 'target uri'
    callback {
        start = 0,
        finish = 0,
        uri = uri
    }
end

local function parseClass(callback, vm, source)
    local className = source:get 'emmy class'
    vm.emmyMgr:eachClass(className, function (class)
        if Mode == 'definition' then
            if class.type == 'emmy.class' or class.type == 'emmy.alias' then
                local src = class:getSource()
                callback(src)
            end
        elseif Mode == 'reference' then
            if class.type == 'emmy.class' or class.type == 'emmy.alias' or class.type == 'emmy.typeUnit' then
                local src = class:getSource()
                callback(src)
            end
        end
    end)
end

local function parseSee(callback, vm, source)
    local see = source:get 'emmy see'
    local className = see[1][1]
    local childName = see[2][1]
    vm.emmyMgr:eachClass(className, function (class)
        ---@type value
        local value = class:getValue()
        local child = value:getChild(childName, nil, source.uri)
        parseValueByValue(callback, vm, source, child)
    end)
end

local function parseFunction(callback, vm, source)
    if Mode == 'definition' then
        callback(source:bindFunction():getSource())
        source:bindFunction():eachInfo(function (info, src)
            if info.type == 'set' or info.type == 'local' then
                if vm.uri == src:getUri() then
                    if source.id >= src.id then
                        callback(src)
                    end
                else
                    callback(src)
                end
            end
        end)
    elseif Mode == 'reference' then
        callback(source:bindFunction():getSource())
        source:bindFunction():eachInfo(function (info, src)
            if info.type == 'set' or info.type == 'local' or info.type == 'get' then
                callback(src)
            end
        end)
    end
end

local function parseScriptUri(callback, vm, source)
    local value = source:bindValue()
    if value and vm.lsp then
        local path = vm:findPathByScript(value)
        if path then
            local ws = vm.lsp:findWorkspaceFor(vm:getUri())
            if not ws then
                return
            end
            local scriptUri = ws:searchPath(vm:getUri(), path, true)
            if scriptUri then
                callback{
                    start = 0,
                    finish = math.huge,
                    uri = scriptUri
                }
            end
        end
    end
end

local function makeList(source)
    local list = {}
    local mark = {}
    return list, function (src)
        if mark[src] then
            return
        end
        mark[src] = true
        list[#list+1] = {
            src.start,
            src.finish,
            src.uri
        }
    end
end

return function (vm, pos, mode)
    local filter = {
        ['name']           = true,
        ['string']         = true,
        ['number']         = true,
        ['boolean']        = true,
        ['label']          = true,
        ['goto']           = true,
        ['function']       = true,
        ['...']            = true,
        ['emmyName']       = true,
        ['emmyIncomplete'] = true,
    }
    local source = findSource(vm, pos, filter)
    if not source then
        return nil
    end
    Mode = mode
    local list, callback = makeList(source)
    local isGlobal
    if source:bindLocal() then
        parseLocal(callback, vm, source)
    end
    if source:bindValue() then
        isGlobal = parseValue(callback, vm, source)
        parseScriptUri(callback, vm, source)
    end
    if source:bindLabel() then
        parseLabel(callback, vm, source:bindLabel())
    end
    if source:bindFunction() then
        parseFunction(callback, vm, source)
    end
    if source:get 'target uri' then
        jumpUri(callback, vm, source)
    end
    if source:get 'in index' then
        isGlobal = parseValue(callback, vm, source)
    end
    if source:get 'emmy class' then
        parseClass(callback, vm, source)
    end
    if source:get 'emmy see' then
        parseSee(callback, vm, source)
    end

    if #list == 0 then
        parseValueSimily(callback, vm, source)
    end

    return list, isGlobal
=======
local guide      = require 'core.guide'
local workspace  = require 'workspace'
local files      = require 'files'
local vm         = require 'vm'
local findSource = require 'core.find-source'
local rojo       = require "library.rojo"

local function sortResults(results)
    -- 先按照顺序排序
    table.sort(results, function (a, b)
        local u1 = guide.getUri(a.target)
        local u2 = guide.getUri(b.target)
        if u1 == u2 then
            return a.target.start < b.target.start
        else
            return u1 < u2
        end
    end)
    -- 如果2个结果处于嵌套状态，则取范围小的那个
    local lf, lu
    for i = #results, 1, -1 do
        local res  = results[i].target
        local f    = res.finish
        local uri = guide.getUri(res)
        if lf and f > lf and uri == lu then
            table.remove(results, i)
        else
            lu = uri
            lf = f
        end
    end
end

local accept = {
    ['local']       = true,
    ['setlocal']    = true,
    ['getlocal']    = true,
    ['field']       = true,
    ['method']      = true,
    ['setglobal']   = true,
    ['getglobal']   = true,
    ['string']      = true,
    ['boolean']     = true,
    ['number']      = true,
    ['...']         = true,

    ['doc.type.name']    = true,
    ['doc.class.name']   = true,
    ['doc.extends.name'] = true,
    ['doc.alias.name']   = true,
    ['doc.see.name']     = true,
    ['doc.see.field']    = true,

    ['type.name']   = true
}

local function checkScriptPath(results, value, source)
    local path = rojo:findPathByScript(value)
    if path then
        local uris = workspace.findUrisByRequirePath(path)
        if uris then
            for i, uri in ipairs(uris) do
                results[#results+1] = {
                    uri    = files.getOriginUri(uri),
                    source = source,
                    target = {
                        start  = 0,
                        finish = 0,
                        uri    = uri,
                    }
                }
            end
        end
    end
end

local function convertIndex(source)
    if not source then
        return
    end
    if source.type == 'string'
    or source.type == 'boolean'
    or source.type == 'number' then
        local parent = source.parent
        if not parent then
            return
        end
        if parent.type == 'setindex'
        or parent.type == 'getindex'
        or parent.type == 'tableindex' then
            return parent
        end
    end
    return source
end

local function findTypeAlias(source)
    if source.typeAlias then
        return source.typeAlias
    elseif source.parent and source.parent.type == "type.module" then
        return vm.getModuleTypeAlias(source.parent)
    end
end

return function (uri, offset)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end

    local source = convertIndex(findSource(ast, offset, accept))
    if not source then
        return nil
    end

    local results = {}

    local defs = vm.getDefs(source, 0, {skipType = true})
    if source.type == "type.name" then
        defs[#defs+1] = findTypeAlias(source)
    end

    local values = {}
    for _, src in ipairs(defs) do
        local value = guide.getObjectValue(src)
        if value and value ~= src then
            values[value] = true
        end
    end
    for _, src in ipairs(defs) do
        if src.dummy then
            goto CONTINUE
        end
        if values[src] then
            goto CONTINUE
        end
        if src.value and src.value.path then
            checkScriptPath(results, src.value, source)
            goto CONTINUE
        end
        local root = guide.getRoot(src)
        if not root then
            goto CONTINUE
        end
        src = src.field or src.method or src.index or src
        if src.type == 'table' and src.parent.type ~= 'return' then
            goto CONTINUE
        end
        if  src.type == 'doc.class.name'
        and source.type ~= 'doc.type.name'
        and source.type ~= 'doc.extends.name'
        and source.type ~= 'doc.see.name' then
            goto CONTINUE
        end
        results[#results+1] = {
            target = src,
            uri    = files.getOriginUri(root.uri),
            source = source,
        }
        ::CONTINUE::
    end

    if #results == 0 then
        return nil
    end

    sortResults(results)

    return results
>>>>>>> origin/master
end
