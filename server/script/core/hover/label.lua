local buildName   = require 'core.hover.name'
local buildArg    = require 'core.hover.arg'
local buildReturn = require 'core.hover.return'
local buildTable  = require 'core.hover.table'
local buildGeneric= require 'core.hover.generic'
local vm          = require 'vm'
local util        = require 'utility'
local guide       = require 'core.guide'
local lang        = require 'language'
local config      = require 'config'
local files       = require 'files'

local function asFunction(source, oop)
    local name
    name, oop   = buildName(source, oop)
    local gen   = buildGeneric(source)
    local arg   = buildArg(source, oop)
    local rtn   = buildReturn(source)
    local lines = {}
    lines[1] = ('function %s%s(%s)'):format(name, gen, arg)
    if rtn then
        lines[2] = INV .. rtn .. INV
    end
    return table.concat(lines, '\n')
end

local function asDocFunction(source)
    local name = buildName(source)
    local arg  = buildArg(source)
    local rtn  = buildReturn(source)
    local lines = {}
    lines[1] = ('function %s(%s)'):format(name, arg)
    if rtn then
        lines[2] = INV .. rtn .. INV
    end
    return table.concat(lines, '\n')
end

local function asFunctionType(source, oop)
    local name
    name, oop   = buildName(source.parent, oop)
    local gen   = buildGeneric(source)
    local arg   = buildArg(source, oop)
    local rtn   = buildReturn(source)
    local lines = {}
    lines[1] = ('function %s%s(%s)'):format(name, gen, arg)
    if rtn then
        lines[2] = INV .. rtn .. INV
    end
    return table.concat(lines, '\n')
end


local function asDocTypeName(source)
    for _, doc in ipairs(vm.getDocTypes(source[1])) do
        if doc.type == 'doc.class.name' then
            return 'class ' .. source[1]
        end
        if doc.type == 'doc.alias.name' then
            local extends = doc.parent.extends
            return lang.script('HOVER_EXTENDS', vm.getInferType(extends))
        end
    end
end

local function asValue(source, title)
    local name    = buildName(source):gsub("%:", ".")
    local type    = vm.getTypeString(source, 0)
    local class   = nil--vm.getClass(source, 0)
    local literal = vm.getInferLiteral(source, 0)
    local cont
    if vm.hasInferType(source, "table", 0)
    and #vm.getFields(source, 0, {searchAll = true}) > 0 then
        cont = buildTable(source)
    end
    for _, def in ipairs(vm.getDefs(source, 0)) do
        if def.kind then
            title = def.kind
            break
        end
    end
    local pack = {}
    pack[#pack+1] = title
    pack[#pack+1] = name .. ':'
    if  cont
    and (  type == 'table'
        or type == 'any'
        or type == 'nil') then
        type = nil
    end
    if class then
        pack[#pack+1] = class
    else
        pack[#pack+1] = type
    end
    if literal then
        pack[#pack+1] = '='
        pack[#pack+1] = literal
    end
    if cont then
        pack[#pack+1] = cont
    end
    if source.extra then
        pack[#pack+1] = source.extra
    end
    return table.concat(pack, ' ')
end

local function asLocal(source)
    return asValue(source, 'local')
end

local function asGlobal(source)
    return asValue(source, 'global')
end

local function isGlobalField(source)
    if source.type == 'field'
    or source.type == 'method' then
        source = source.parent
    end
    if source.type == 'setfield'
    or source.type == 'getfield'
    or source.type == 'setmethod'
    or source.type == 'getmethod' then
        local node = source.node
        if node.type == 'setglobal'
        or node.type == 'getglobal' then
            return true
        end
        return isGlobalField(node)
    elseif source.type == 'tablefield' then
        local parent = source.parent
        if parent.type == 'setglobal'
        or parent.type == 'getglobal' then
            return true
        end
        return isGlobalField(parent)
    else
        return false
    end
end

local function asField(source)
    if isGlobalField(source) then
        return asGlobal(source)
    end
    return asValue(source, 'field')
end

local function asDocField(source)
    local name  = source.field[1]
    local class
    for _, doc in ipairs(source.bindGroup) do
        if doc.type == 'doc.class' then
            class = doc
            break
        end
    end
    local infers = {}
    for _, infer in ipairs(vm.getInfers(source.extends) or {}) do
        infers[#infers+1] = infer
    end
    if not class then
        return ('field ?.%s: %s'):format(
            name,
            guide.viewInferType(infers)
        )
    end
    return ('field %s.%s: %s'):format(
        class.class[1],
        name,
        guide.viewInferType(infers)
    )
end

local function asString(source)
    local str = source[1]
    if type(str) ~= 'string' then
        return ''
    end
    local len = #str
    local charLen = util.utf8Len(str, 1, -1)
    if len == charLen then
        return lang.script('HOVER_STRING_BYTES', len)
    else
        return lang.script('HOVER_STRING_CHARACTERS', len, charLen)
    end
end

local function formatNumber(n)
    local str = ('%.10f'):format(n)
    str = str:gsub('%.?0*$', '')
    return str
end

local function asNumber(source)
    if not config.config.hover.viewNumber then
        return nil
    end
    local num = source[1]
    if type(num) ~= 'number' then
        return nil
    end
    local uri  = guide.getUri(source)
    local text = files.getText(uri)
    if not text then
        return nil
    end
    local raw = text:sub(source.start, source.finish)
    if not raw or not raw:find '[^%-%d%.]' then
        return nil
    end
    return formatNumber(num)
end

return function (source, oop)
    if source.type == 'function' then
        return asFunction(source, oop)
    elseif source.type == 'local'
    or     source.type == 'getlocal'
    or     source.type == 'setlocal' then
        return asLocal(source)
    elseif source.type == 'setglobal'
    or     source.type == 'getglobal' then
        return asGlobal(source)
    elseif source.type == 'getfield'
    or     source.type == 'setfield'
    or     source.type == 'getmethod'
    or     source.type == 'setmethod'
    or     source.type == 'tablefield'
    or     source.type == 'field'
    or     source.type == 'method' then
        return asField(source)
    elseif source.type == 'string' then
        return asString(source)
    elseif source.type == 'number' then
        return asNumber(source)
    elseif source.type == 'doc.type.function' then
        return asDocFunction(source)
    elseif source.type == 'doc.type.name' then
        return asDocTypeName(source)
    elseif source.type == 'doc.field' then
        return asDocField(source)
    elseif source.type == 'type.field.key' then
        return asValue(source.parent.value, source.parent.kind or 'field')
    elseif source.type == 'type.field' then
        return asValue(source.value, source.kind or 'field')
    elseif source.type == "type.library" then
        return asValue(source, source.kind or 'global')
    elseif source.type == 'type.function' then
        return asFunctionType(source, oop)
    end
end
