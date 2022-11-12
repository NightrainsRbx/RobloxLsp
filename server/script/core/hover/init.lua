local files      = require 'files'
local guide      = require 'core.guide'
local vm         = require 'vm'
local getLabel   = require 'core.hover.label'
local getDesc    = require 'core.hover.description'
local buildName  = require 'core.hover.name'
local buildArg   = require 'core.hover.arg'
local buildReturn = require 'core.hover.return'
local util       = require 'utility'
local findSource = require 'core.find-source'
local lang       = require 'language'
local markdown   = require 'provider.markdown'
local furi       = require 'file-uri'

local function getPath(source)
    for _, def in ipairs(vm.getDefs(source)) do
        if def.type == "type.library" and def.value.uri then
            return furi.decode(def.value.uri)
        end
    end
end

local function eachFunctionAndOverload(value, callback)
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

local function getHoverAsValue(source)
    local oop = source.type == 'method'
             or source.type == 'getmethod'
             or source.type == 'setmethod'
    local label = getLabel(source, oop)
    local desc  = getDesc(source)
    if not desc then
        local values = vm.getDefs(source, 0)
        for _, def in ipairs(values) do
            desc = getDesc(def)
            if desc then
                break
            end
        end
    end
    return {
        label       = label and INV .. label,
        source      = source,
        description = desc,
        path        = getPath(source)
    }
end

local function getHoverAsFunction(source, oop)
    local values = vm.getDefs(source, 0)
    local desc   = getDesc(source)
    local labels = {}
    local defs = 0
    local protos = 0
    local other = 0
    -- oop = oop or source.type == 'method'
    -- or source.type == 'getmethod'
    -- or source.type == 'setmethod'
    local mark = {}
    for _, def in ipairs(values) do
        def = guide.getObjectValue(def) or def
        if def.type == 'function'
        or def.type == 'doc.type.function' then
            eachFunctionAndOverload(def, function (value)
                if mark[value] then
                    return
                end
                mark[value] =true
                local label = getLabel(value, oop)
                if label then
                    defs = defs + 1
                    labels[label] = (labels[label] or 0) + 1
                    if labels[label] == 1 then
                        protos = protos + 1
                    end
                end
                desc = desc or getDesc(value)
            end)
        elseif def.type == 'table'
        or     def.type == 'boolean'
        or     def.type == 'string'
        or     def.type == 'number' then
            other = other + 1
            desc = desc or getDesc(def)
        end
    end

    if defs == 0 then
        return getHoverAsValue(source)
    end

    if defs == 1 and other == 0 then
        return {
            label       = next(labels),
            source      = source,
            description = desc,
        }
    end

    local lines = {}
    if defs > 1 then
        lines[#lines+1] = lang.script('HOVER_MULTI_DEF_PROTO', defs, protos)
    end
    if other > 0 then
        lines[#lines+1] = lang.script('HOVER_MULTI_PROTO_NOT_FUNC', other)
    end
    if defs > 1 then
        for label, count in util.sortPairs(labels) do
            lines[#lines+1] = label--('(%d) %s'):format(count, label)
        end
    else
        lines[#lines+1] = next(labels)
    end
    local label = table.concat(lines, '\n')
    return {
        label       = label,
        source      = source,
        description = desc,
    }
end

local function getHoverAsTypeFunction(source, values, oop)
    local desc = {}
    local name
    local lines = {}
    name, oop   = buildName(source, oop)
    local defs = 0
    local other = 0
    for _, value in ipairs(values) do
        if value.type == "type.function" then
            defs = defs + 1
            local arg   = buildArg(value, oop)
            local rtn   = buildReturn(value)
            lines[#lines+1] = ('function %s(%s)'):format(name, arg)
            if value.parent.description then
                desc[#desc+1] = value.parent.description
            end
            if rtn then
                lines[#lines+1] = INV .. rtn .. INV
            end
        else
            other = other + 1
        end
    end
    if other > 0 then
        table.insert(lines, 1, lang.script('HOVER_MULTI_PROTO_NOT_FUNC', other))
    end
    if defs > 1 then
        table.insert(lines, 1, lang.script('HOVER_MULTI_DEF_PROTO', defs, defs))
    end
    return {
        label       = table.concat(lines, '\n'),
        source      = source,
        description = #desc > 0 and table.concat(desc, '\n') or getDesc(source),
    }
end

local function getHoverAsDocName(source)
    local label = getLabel(source)
    local desc  = getDesc(source)
    return {
        label       = label,
        source      = source,
        description = desc,
    }
end

local function getHoverAsTypeAlias(source)
    local typeAlias = source.parent
    local label = "type " .. typeAlias.name[1]
    if typeAlias.generics then
        label = label .. guide.buildTypeAnn(typeAlias.generics)
    end
    label = label .. " = " .. guide.buildTypeAnn(typeAlias.value)
    return {
        label = label,
        source = source
    }
end

local function getHoverAsTypeName(source)
    local label
    local typeAlias = vm.getTypeAlias(source)
    if typeAlias then
        label = getHoverAsTypeAlias(typeAlias.name).label
    else
        label = INV .. "type " .. guide.buildTypeAnn(source)
    end
    return {
        label       = label,
        source      = source,
    }
end

local function getHover(source, oop)
    if source.type == 'doc.type.name' then
        return getHoverAsDocName(source)
    elseif source.type == 'type.name' then
        return getHoverAsTypeName(source)
    elseif source.type == 'type.alias.name' then
        return getHoverAsTypeAlias(source)
    else
        local infers = vm.getInfers(source, 0)
        for i = 1, #infers do
            local infer = infers[i]
            if infer.type == "function" then
                return getHoverAsFunction(source, oop)
            elseif infer.source then
                if infer.source.type == "type.function" then
                    return getHoverAsTypeFunction(source, {infer.source}, oop)
                elseif infer.source.type == "type.inter" then
                    local values = guide.getAllValuesInType(infer.source, "type.function")
                    if #values > 0 then
                        return getHoverAsTypeFunction(source, values, oop)
                    end
                end
            end
        end
    end
    return getHoverAsValue(source)
end

local accept = {
    ['local']          = true,
    ['setlocal']       = true,
    ['getlocal']       = true,
    ['setglobal']      = true,
    ['getglobal']      = true,
    ['field']          = true,
    ['method']         = true,
    ['string']         = true,
    ['number']         = true,
    ['doc.type.name']  = true,
    ['function']       = true,
    ['type.name']      = true,
    ['type.alias.name'] = true,
    ['type.field.key'] = true,
}

local function getHoverByUri(uri, offset)
    local ast = files.getAst(uri)
    if not ast then
        return nil
    end
    local source = findSource(ast, offset, accept)
    if not source then
        return nil
    end
    local hover = getHover(source)
    if SHOWSOURCE then
        hover.description = ('%s\n---\n\n```lua\n%s\n```'):format(
            hover.description or '',
            util.dump(source, {
                deep = 1,
            })
        )
    end
    return hover
end

return {
    get   = getHover,
    byUri = getHoverByUri,
}
