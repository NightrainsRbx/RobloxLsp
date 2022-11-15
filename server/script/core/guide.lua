local util         = require 'utility'
local rbxlibs      = require 'library.rbxlibs'
local config       = require 'config'
local lang         = require 'language'
local error        = error
local type         = type
local next         = next
local tostring     = tostring
local ipairs       = ipairs
local tableSort    = table.sort
local tableConcat  = table.concat
local pairs        = pairs
local setmetatable = setmetatable
local osClock      = os.clock
local DEVELOP      = _G.DEVELOP
local log          = log
local _G           = _G

local SET_VALUE_LIMIT = 10

---@class parser.guide.object

local function logWarn(...)
    log.warn(...)
end

---@class guide
---@field debugMode boolean
local m = {}

m.ANY = {"<ANY>"}

local blockTypes = {
    ['while']       = true,
    ['in']          = true,
    ['loop']        = true,
    ['repeat']      = true,
    ['do']          = true,
    ['function']    = true,
    ['ifblock']     = true,
    ['elseblock']   = true,
    ['elseifblock'] = true,
    ['main']        = true,
}

local breakBlockTypes = {
    ['while']       = true,
    ['in']          = true,
    ['loop']        = true,
    ['repeat']      = true,
}

m.childMap = {
    ['main']        = {'#', 'docs'},
    ['repeat']      = {'#', 'filter'},
    ['while']       = {'filter', '#'},
    ['in']          = {'keys', '#'},
    ['loop']        = {'loc', 'max', 'step', '#'},
    ['if']          = {'#'},
    ['ifblock']     = {'filter', '#'},
    ['elseifblock'] = {'filter', '#'},
    ['elseblock']   = {'#'},
    ['setfield']    = {'node', 'field', 'value'},
    ['setglobal']   = {'value'},
    ['local']       = {'typeAnn', 'value'},
    ['setlocal']    = {'value'},
    ['return']      = {'#'},
    ['do']          = {'#'},
    ['select']      = {'vararg'},
    ['table']       = {'#'},
    ['tableindex']  = {'index', 'value'},
    ['tablefield']  = {'field', 'value'},
    ['function']    = {'args', '#', 'returnTypeAnn', 'generics'},
    ['funcargs']    = {'#'},
    ['setmethod']   = {'node', 'method', 'value'},
    ['getmethod']   = {'node', 'method'},
    ['setindex']    = {'node', 'index', 'value'},
    ['getindex']    = {'node', 'index'},
    ['paren']       = {'exp'},
    ['call']        = {'node', 'args'},
    ['callargs']    = {'#'},
    ['getfield']    = {'node', 'field'},
    ['list']        = {'#'},
    ['binary']      = {1, 2},
    ['unary']       = {1},
    ['type.ann']    = {'value'},
    ['type.alias']  = {'name', 'value', 'generics'},
    ['type.assert'] = {1, 2},
    ['...']         = {'typeAnn'},
    ['ifexp']       = {'filter', '#'},
    ['elseifexp']   = {'filter', 1},

    ['type.list']        = {"#"},
    ['type.table']       = {"#"},
    ['type.union']       = {"#"},
    ['type.inter']       = {"#"},
    ['type.generics']    = {"#"},
    ['type.module']      = {"#"},
    ['type.field']       = {"key", "value"},
    ['type.index']       = {"key", "value"},
    ['type.function']    = {"args", "returns", 'generics'},
    ['type.name']        = {"generics"},
    ['type.parameter']   = {"default"},
    ['type.genericpack'] = {"default"},
    ['type.variadic']    = {"value"},
    ['type.typeof']      = {"value"},
    ['type.library']     = {"value"},
    ['type.meta']        = {"#"},

    ['doc']                = {'#'},
    ['doc.class']          = {'class', '#extends', 'comment'},
    ['doc.type']           = {'#types', '#enums', 'name', 'comment'},
    ['doc.alias']          = {'alias', 'extends', 'comment'},
    ['doc.param']          = {'param', 'extends', 'comment'},
    ['doc.return']         = {'#returns', 'comment'},
    ['doc.field']          = {'field', 'extends', 'comment'},
    ['doc.generic']        = {'#generics', 'comment'},
    ['doc.generic.object'] = {'generic', 'extends', 'comment'},
    ['doc.vararg']         = {'vararg', 'comment'},
    ['doc.type.array']     = {'node'},
    ['doc.type.table']     = {'node', 'key', 'value', 'comment'},
    ['doc.type.function']  = {'#args', '#returns', 'comment'},
    ['doc.type.typeliteral']  = {'node'},
    ['doc.type.arg']       = {'extends'},
    ['doc.overload']       = {'overload', 'comment'},
    ['doc.see']            = {'name', 'field', 'comment'},
    ['doc.diagnostic']     = {'#names', 'comment'},
}

m.actionMap = {
    ['main']        = {'#'},
    ['repeat']      = {'#'},
    ['while']       = {'#'},
    ['in']          = {'#'},
    ['loop']        = {'#'},
    ['if']          = {'#'},
    ['ifblock']     = {'#'},
    ['elseifblock'] = {'#'},
    ['elseblock']   = {'#'},
    ['do']          = {'#'},
    ['function']    = {'#'},
    ['funcargs']    = {'#'},
}

local TypeSort = {
    ['boolean']  = 1,
    ['string']   = 2,
    ['integer']  = 3,
    ['number']   = 4,
    ['table']    = 5,
    ['function'] = 6,
    ['true']     = 101,
    ['false']    = 102,
    ['nil']      = 999,
}

m.typeAnnTypes = {
    ["type.name"] = true,
    ["type.list"] = true,
    ["type.table"] = true,
    ["type.function"] = true,
    ["type.union"] = true,
    ["type.inter"] = true,
    ["type.index"] = true,
    ["type.field"] = true,
    ["type.module"] = true,
    ["type.variadic"] = true,
    ["type.typeof"] = true,
    ["type.genericpack"] = true,
    ["type.singleton.string"] = true,
    ["type.singleton.boolean"] = true,
    ["type.library"] = true
}

m.binaryMeta = {
    ["+"] = "__add",
    ["-"] = "__sub",
    ["*"] = "__mul",
    ["/"] = "__div",
    ["%"] = "__mod",
    ["^"] = "__pow",
    ["=="] = "__eq",
    ["~="] = "__eq",
    ["<"] = "__lt",
    [">"] = "__lt",
    ["<="] = "__le",
    [">="] = "__le",
    [".."] = "__concat"
}

m.unaryMeta = {
    ["-"] = "__unm",
    ["#"] = "__len"
}

local NIL = setmetatable({'<nil>'}, { __tostring = function () return 'nil' end })

--- 是否是字面量
---@param obj parser.guide.object
---@return boolean
function m.isLiteral(obj)
    local tp = obj.type
    return tp == 'nil'
        or tp == 'boolean'
        or tp == 'string'
        or tp == 'number'
        or tp == 'table'
        or tp == 'function'
end

function m.isTypeAnn(obj)
    return m.typeAnnTypes[(m.getObjectValue(obj) or obj).type]
end

--- 获取字面量
---@param obj parser.guide.object
---@return any
function m.getLiteral(obj)
    local tp = obj.type
    if     tp == 'boolean' then
        return obj[1]
    elseif tp == 'string' then
        return obj[1]
    elseif tp == 'number' then
        return obj[1]
    end
    return nil
end

--- 寻找父函数
---@param obj parser.guide.object
---@return parser.guide.object
function m.getParentFunction(obj)
    for _ = 1, 1000 do
        obj = obj.parent
        if not obj then
            break
        end
        local tp = obj.type
        if tp == 'function' or tp == 'main' then
            return obj
        end
    end
    return nil
end

--- 寻找父的table类型 doc.type.table
---@param obj parser.guide.object
---@return parser.guide.object
function m.getParentDocTypeTable(obj)
    for _ = 1, 1000 do
        local parent = obj.parent
        if not parent then
            return nil
        end
        if parent.type == 'doc.type.table' then
            return obj
        end
        obj = parent
    end
    error('guide.getParentDocTypeTable overstack')
end

--- 寻找所在区块
---@param obj parser.guide.object
---@return parser.guide.object
function m.getBlock(obj)
    for _ = 1, 1000 do
        if not obj then
            return nil
        end
        local tp = obj.type
        if blockTypes[tp] then
            return obj
        end
        if obj == obj.parent then
            error('obj == obj.parent?', obj.type)
        end
        obj = obj.parent
    end
    error('guide.getBlock overstack')
end

--- 寻找所在父区块
---@param obj parser.guide.object
---@return parser.guide.object
function m.getParentBlock(obj)
    for _ = 1, 1000 do
        obj = obj.parent
        if not obj then
            return nil
        end
        local tp = obj.type
        if blockTypes[tp] then
            return obj
        end
    end
    error('guide.getParentBlock overstack')
end

function m.hasParent(obj, parent)
    for _ = 1, 1000 do
        obj = obj.parent
        if not obj then
            return false
        end
        if obj == parent then
            return true
        end
    end
    error('guide.hasParent overstack')
end

--- 寻找所在可break的父区块
---@param obj parser.guide.object
---@return parser.guide.object
function m.getBreakBlock(obj)
    for _ = 1, 1000 do
        obj = obj.parent
        if not obj then
            return nil
        end
        local tp = obj.type
        if breakBlockTypes[tp] then
            return obj
        end
        if tp == 'function' then
            return nil
        end
    end
    error('guide.getBreakBlock overstack')
end

--- 寻找doc的主体
---@param obj parser.guide.object
---@return parser.guide.object
function m.getDocState(obj)
    for _ = 1, 1000 do
        local parent = obj.parent
        if not parent then
            return obj
        end
        if parent.type == 'doc' then
            return obj
        end
        obj = parent
    end
    error('guide.getDocState overstack')
end

--- 寻找所在父类型
---@param obj parser.guide.object
---@return parser.guide.object
function m.getParentType(obj, want)
    for _ = 1, 1000 do
        obj = obj.parent
        if not obj then
            return nil
        end
        if want == obj.type then
            return obj
        end
    end
    error('guide.getParentType overstack')
end

--- 寻找根区块
---@param obj parser.guide.object
---@return parser.guide.object
function m.getRoot(obj)
    for _ = 1, 1000 do
        if obj.type == 'main' then
            return obj
        end
        local parent = obj.parent
        if not parent then
            return nil
        end
        obj = parent
    end
    error('guide.getRoot overstack')
end

---@param obj parser.guide.object
---@return string
function m.getUri(obj)
    if obj.uri then
        return obj.uri
    end
    local root = m.getRoot(obj)
    if root then
        return root.uri
    end
    return ''
end

function m.getENV(source, start)
    if not start then
        start = 1
    end
    return m.getLocal(source, '_ENV', start)
        or m.getLocal(source, '@fenv', start)
end

--- 寻找函数的不定参数，返回不定参在第几个参数上，以及该参数对象。
--- 如果函数是主函数，则返回`0, nil`。
---@return table
---@return integer
function m.getFunctionVarArgs(func)
    if func.type == 'main' then
        return 0, nil
    end
    if func.type ~= 'function' then
        return nil, nil
    end
    local args = func.args
    if not args then
        return nil, nil
    end
    for i = 1, #args do
        local arg = args[i]
        if arg.type == '...' then
            return i, arg
        end
    end
    return nil, nil
end

--- 获取指定区块中可见的局部变量
---@param block table
---@param name string {comment = '变量名'}
---@param pos integer {comment = '可见位置'}
function m.getLocal(block, name, pos)
    block = m.getBlock(block)
    for _ = 1, 1000 do
        if not block then
            return nil
        end
        local locals = block.locals
        local res
        if not locals then
            goto CONTINUE
        end
        for i = 1, #locals do
            local loc = locals[i]
            if loc.effect > pos then
                break
            end
            if loc[1] == name then
                if not res or res.effect < loc.effect then
                    res = loc
                end
            end
        end
        if res then
            return res, res
        end
        ::CONTINUE::
        block = m.getParentBlock(block)
    end
    error('guide.getLocal overstack')
end

function m.getVisibleTypeAlias(source)
    local results = {}
    local parent = source
    for _ = 1, 1000 do
        parent = parent.parent
        if not parent then
            break
        end
        if parent.type == "type.function" or parent.type == "function" or parent.type == "type.alias" then
            if parent.generics then
                for _, generic in ipairs(parent.generics) do
                    results[#results+1] = generic
                end
            end
        end
    end
    local block = m.getBlock(source)
    for _ = 1, 1000 do
        if not block then
            break
        end
        local types = block.types
        if not types then
            goto CONTINUE
        end
        for i = 1, #types do
            results[#results+1] = types[i]
        end
        ::CONTINUE::
        block = m.getParentBlock(block)
    end
    local files = require("files")
    for libUri in pairs(files.libraryMap) do
        local state = files.getAst(libUri)
        if state and state.ast.types then
            for _, alias in ipairs(state.ast.types) do
                if alias.export then
                    results[#results+1] = alias
                end
            end
        end
    end
    return results
end

function m.getTypeAliasInAst(source, name)
    local block = m.getBlock(source)
    for _ = 1, 1000 do
        if not block then
            break
        end
        for i = 1, #block do
            local obj = block[i]
            if obj.type == "type.alias" and obj.name[1] == name then
                return obj
            end
        end
        block = m.getParentBlock(block)
    end
    return nil
end

--- 获取指定区块中所有的可见局部变量名称
function m.getVisibleLocals(block, pos, set)
    local result = {}
    m.eachSourceContain(m.getRoot(block), pos, function (source)
        local locals = source.locals
        if locals then
            for i = 1, #locals do
                local loc = locals[i]
                local name = loc[1]
                if loc.effect <= pos then
                    result[name] = loc
                    if set and loc.range then
                        for _, ref in ipairs(loc.ref or {}) do
                            if ref.type == "setlocal" and ref.range then
                                if ref.range <= pos and ref.range >= result[name].range then
                                    result[name] = ref
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return result
end

--- 获取指定区块中可见的标签
---@param block table
---@param name string {comment = '标签名'}
function m.getLabel(block, name)
    block = m.getBlock(block)
    for _ = 1, 1000 do
        if not block then
            return nil
        end
        local labels = block.labels
        if labels then
            local label = labels[name]
            if label then
                return label
            end
        end
        if block.type == 'function' then
            return nil
        end
        block = m.getParentBlock(block)
    end
    error('guide.getLocal overstack')
end

function m.getStartFinish(source)
    local start  = source.start
    local finish = source.finish
    if not start then
        local first = source[1]
        if not first then
            return nil, nil
        end
        local last  = source[#source]
        start  = first.start
        finish = last.finish
    end
    return start, finish
end

function m.getRange(source)
    local start  = source.vstart or source.start
    local finish = source.range  or source.finish
    if not start then
        local first = source[1]
        if not first then
            return nil, nil
        end
        local last  = source[#source]
        start  = first.vstart or first.start
        finish = last.range   or last.finish
    end
    return start, finish
end

--- 判断source是否包含offset
function m.isContain(source, offset)
    local start, finish = m.getStartFinish(source)
    if not start then
        return false
    end
    return start <= offset and finish >= offset
end

--- 判断offset在source的影响范围内
---
--- 主要针对赋值等语句时，key包含value
function m.isInRange(source, offset)
    local start, finish = m.getRange(source)
    if not start then
        return false
    end
    return start <= offset and finish >= offset
end

function m.isBetween(source, tStart, tFinish)
    local start, finish = m.getStartFinish(source)
    if not start then
        return false
    end
    return start <= tFinish and finish >= tStart
end

function m.isBetweenRange(source, tStart, tFinish)
    local start, finish = m.getRange(source)
    if not start then
        return false
    end
    return start <= tFinish and finish >= tStart
end

--- 添加child
function m.addChilds(list, obj, map)
    local keys = map[obj.type]
    if keys then
        for i = 1, #keys do
            local key = keys[i]
            if key == '#' then
                for i = 1, #obj do
                    list[#list+1] = obj[i]
                end
            elseif obj[key] then
                list[#list+1] = obj[key]
            elseif type(key) == 'string'
            and key:sub(1, 1) == '#' then
                key = key:sub(2)
                if obj[key] then
                    for i = 1, #obj[key] do
                        list[#list+1] = obj[key][i]
                    end
                end
            end
        end
    end
end

--- 遍历所有包含offset的source
function m.eachSourceContain(ast, offset, callback)
    local list = { ast }
    local mark = {}
    while true do
        local len = #list
        if len == 0 then
            return
        end
        local obj = list[len]
        list[len] = nil
        if not mark[obj] then
            mark[obj] = true
            if m.isInRange(obj, offset) then
                if m.isContain(obj, offset) then
                    local res = callback(obj)
                    if res ~= nil then
                        return res
                    end
                end
                m.addChilds(list, obj, m.childMap)
            end
        end
    end
end

--- 遍历所有在某个范围内的source
function m.eachSourceBetween(ast, start, finish, callback)
    local list = { ast }
    local mark = {}
    while true do
        local len = #list
        if len == 0 then
            return
        end
        local obj = list[len]
        list[len] = nil
        if not mark[obj] then
            mark[obj] = true
            if m.isBetweenRange(obj, start, finish) then
                if m.isBetween(obj, start, finish) then
                    local res = callback(obj)
                    if res ~= nil then
                        return res
                    end
                end
                m.addChilds(list, obj, m.childMap)
            end
        end
    end
end

--- 遍历所有指定类型的source
function m.eachSourceType(ast, type, callback)
    local cache = ast._typeCache
    if not cache then
        cache = {}
        ast._typeCache = cache
        m.eachSource(ast, function (source)
            local tp = source.type
            if not tp then
                return
            end
            local myCache = cache[tp]
            if not myCache then
                myCache = {}
                cache[tp] = myCache
            end
            myCache[#myCache+1] = source
        end)
    end
    local myCache = cache[type]
    if not myCache then
        return
    end
    for i = #myCache, 1, -1 do
        callback(myCache[i])
    end
end

--- 遍历所有的source
function m.eachSource(ast, callback)
    local list = { ast }
    local mark = {}
    local index = 1
    while true do
        local obj = list[index]
        if not obj then
            return
        end
        list[index] = false
        index = index + 1
        if not mark[obj] then
            mark[obj] = true
            callback(obj)
            m.addChilds(list, obj, m.childMap)
        end
    end
end

--- 获取指定的 special
function m.eachSpecialOf(ast, name, callback)
    local root = m.getRoot(ast)
    if not root.specials then
        return
    end
    local specials = root.specials[name]
    if not specials then
        return
    end
    for i = 1, #specials do
        callback(specials[i])
    end
end

--- 获取偏移对应的坐标
---@param lines table
---@return integer row
---@return integer col
function m.positionOf(lines, offset)
    if offset < 1 then
        return 0, 0
    end
    local lastLine = lines[#lines]
    if offset > lastLine.finish then
        return #lines, offset - lastLine.start
    end
    local min = 1
    local max = #lines
    for _ = 1, 100 do
        if max <= min then
            local line = lines[min]
            return min, offset - line.start + 1
        end
        local row = (max - min) // 2 + min
        local line = lines[row]
        if offset < line.start then
            max = row - 1
        elseif offset > line.finish then
            min = row + 1
        else
            return row, offset - line.start + 1
        end
    end
    error('Stack overflow!')
end

--- 获取坐标对应的偏移
---@param lines table
---@param row integer
---@param col integer
---@return integer {name = 'offset'}
function m.offsetOf(lines, row, col)
    if row < 1 then
        return 0
    end
    if row > #lines then
        local lastLine = lines[#lines]
        return lastLine.finish
    end
    local line = lines[row]
    local len = line.finish - line.start + 1
    if col < 0 then
        return line.start
    elseif col > len then
        return line.finish
    else
        return line.start + col - 1
    end
end

function m.lineContent(lines, text, row, ignoreNL)
    local line = lines[row]
    if not line then
        return ''
    end
    if ignoreNL then
        return text:sub(line.start, line.range)
    else
        return text:sub(line.start, line.finish)
    end
end

function m.lineRange(lines, row, ignoreNL)
    local line = lines[row]
    if not line then
        return 0, 0
    end
    if ignoreNL then
        return line.start, line.range
    else
        return line.start, line.finish
    end
end

function m.lineData(lines, row)
    return lines[row]
end

function m.getKeyTypeOfLiteral(obj)
    if not obj then
        return nil
    end
    local tp = obj.type
    if tp == 'field'
    or     tp == 'method' then
        return 'string'
    elseif tp == 'string' then
        return 'string'
    elseif tp == 'number' then
        return 'number'
    elseif tp == 'boolean' then
        return 'boolean'
    end
end

function m.getKeyType(obj)
    if not obj then
        return nil
    end
    local tp = obj.type
    if tp == 'getglobal'
    or tp == 'setglobal' then
        return 'string'
    elseif tp == 'local'
    or     tp == 'getlocal'
    or     tp == 'setlocal' then
        return 'local'
    elseif tp == 'getfield'
    or     tp == 'setfield'
    or     tp == 'tablefield' then
        return 'string'
    elseif tp == 'getmethod'
    or     tp == 'setmethod' then
        return 'string'
    elseif tp == 'getindex'
    or     tp == 'setindex'
    or     tp == 'tableindex' then
        return m.getKeyTypeOfLiteral(obj.index)
    elseif tp == 'field'
    or     tp == 'method'
    or     tp == 'doc.see.field' then
        return 'string'
    elseif tp == 'doc.class' then
        return 'string'
    elseif tp == 'doc.alias' then
        return 'string'
    elseif tp == 'doc.field' then
        return 'string'
    elseif tp == 'dummy' then
        return 'string'
    elseif tp == "type.library"
    or     tp == "type.field"
    or     tp == "type.field.key" then
        return "string"
    end
    return m.getKeyTypeOfLiteral(obj)
end

function m.getKeyNameOfLiteral(obj)
    if not obj then
        return nil
    end
    local tp = obj.type
    if tp == 'field'
    or     tp == 'method' then
        return obj[1]
    elseif tp == 'string' then
        local s = obj[1]
        if s then
            return s
        end
    elseif tp == 'number' then
        local n = obj[1]
        if n then
            return ('%s'):format(util.viewLiteral(obj[1]))
        end
    elseif tp == 'boolean' then
        local b = obj[1]
        if b then
            return tostring(b)
        end
    end
end

function m.getKeyName(obj)
    if not obj then
        return nil
    end
    local tp = obj.type
    if tp == 'getglobal'
    or tp == 'setglobal' then
        return obj[1]
    elseif tp == 'local'
    or     tp == 'getlocal'
    or     tp == 'setlocal' then
        return obj[1]
    elseif tp == 'getfield'
    or     tp == 'setfield'
    or     tp == 'tablefield' then
        if obj.field then
            return obj.field[1]
        end
    elseif tp == 'getmethod'
    or     tp == 'setmethod' then
        if obj.method then
            return obj.method[1]
        end
    elseif tp == 'getindex'
    or     tp == 'setindex'
    or     tp == 'tableindex' then
        return m.getKeyNameOfLiteral(obj.index)
    elseif tp == 'field'
    or     tp == 'method'
    or     tp == 'doc.see.field' then
        return obj[1]
    elseif tp == 'doc.class' then
        return obj.class[1]
    elseif tp == 'doc.alias' then
        return obj.alias[1]
    elseif tp == 'doc.field' then
        return obj.field[1]
    elseif tp == 'dummy' then
        return obj[1]
    elseif tp == 'type.library' then
        return obj.name
    elseif tp == "type.field" then
        return obj.key[1]
    elseif tp == "type.field.key" then
        return obj[1]
    end
    return m.getKeyNameOfLiteral(obj)
end

function m.getSimpleName(obj)
    if obj.type == 'call' then
        local node = obj.node
        if not node then
            return
        end
        if node.special == 'rawset'
        or node.special == 'rawget' then
            local key = obj.args and obj.args[2]
            return m.getKeyName(key)
        end
        return ('%p'):format(obj)
    elseif obj.type == 'table' then
        return ('%p'):format(obj)
    elseif obj.type == 'select' then
        return ('%p'):format(obj)
    elseif obj.type == 'string' then
        return ('%p'):format(obj)
    elseif obj.type == 'doc.class.name'
    or     obj.type == 'doc.type.name'
    or     obj.type == 'doc.see.name' then
        return ('%s'):format(obj[1])
    elseif obj.type == 'doc.class' then
        return ('%s'):format(obj.class[1])
    end
    return m.getKeyName(obj)
end

local function makeNameType(tp)
    return {
        [1] = tp,
        type = "type.name"
    }
end

function m.searchLibraryChildren(obj)
    local search = {}
    if obj.child then
        search[#search+1] = obj.child
    end
    if obj.type == "type.name" then
        local libObject = rbxlibs.object[obj[1]]
        if libObject then
            if libObject.child then
                search[#search+1] = libObject.child
            end
            if libObject.ref then
                search[#search+1] = libObject.ref
            end
        end
    end
    return search
end

--- 测试 a 到 b 的路径（不经过函数，不考虑 goto），
--- 每个路径是一个 block 。
---
--- 如果 a 在 b 的前面，返回 `"before"` 加上 2个`list<block>`
---
--- 如果 a 在 b 的后面，返回 `"after"` 加上 2个`list<block>`
---
--- 否则返回 `false`
---
--- 返回的2个 `list` 分别为基准block到达 a 与 b 的路径。
---@param a table
---@param b table
---@return string|boolean mode
---@return table pathA?
---@return table pathB?
function m.getPath(a, b, sameFunction)
    --- 首先测试双方在同一个函数内
    if sameFunction and m.getParentFunction(a) ~= m.getParentFunction(b) then
        return false
    end
    local mode
    local objA
    local objB
    if a.finish < b.start then
        mode = 'before'
        objA = a
        objB = b
    elseif a.start > b.finish then
        mode = 'after'
        objA = b
        objB = a
    else
        return 'equal', {}, {}
    end
    local pathA = {}
    local pathB = {}
    for _ = 1, 1000 do
        objA = m.getParentBlock(objA)
        pathA[#pathA+1] = objA
        if (not sameFunction and objA.type == 'function') or objA.type == 'main' then
            break
        end
    end
    for _ = 1, 1000 do
        objB = m.getParentBlock(objB)
        pathB[#pathB+1] = objB
        if (not sameFunction and objA.type == 'function') or objB.type == 'main' then
            break
        end
    end
    -- pathA: {1, 2, 3, 4, 5}
    -- pathB: {5, 6, 2, 3}
    local top = #pathB
    local start
    for i = #pathA, 1, -1 do
        local currentBlock = pathA[i]
        if currentBlock == pathB[top] then
            start = i
            break
        end
    end
    if not start then
        return nil
    end
    -- pathA: {   1, 2, 3}
    -- pathB: {5, 6, 2, 3}
    local extra = 0
    local align = top - start
    for i = start, 1, -1 do
        local currentA = pathA[i]
        local currentB = pathB[i+align]
        if currentA ~= currentB then
            extra = i
            break
        end
    end
    -- pathA: {1}
    local resultA = {}
    for i = extra, 1, -1 do
        resultA[#resultA+1] = pathA[i]
    end
    -- pathB: {5, 6}
    local resultB = {}
    for i = extra + align, 1, -1 do
        resultB[#resultB+1] = pathB[i]
    end
    return mode, resultA, resultB
end

-- 根据语法，单步搜索定义
local function stepRefOfLocal(status, ref, loc, mode)
    local results = {}
    if loc.start ~= 0 and not m.isOpaqued(loc, ref, status) then
        results[#results+1] = loc
    end
    local refs = m.getVisibleRefs(loc, status)
    if not refs then
        return results
    end
    for i = 1, #refs do
        local ref = refs[i]
        if ref.start == 0 then
            goto CONTINUE
        end
        if mode == 'def' then
            if ref.type == 'local'
            or ref.type == 'setlocal' then
                results[#results+1] = ref
            end
        else
            if ref.type == 'local'
            or ref.type == 'setlocal'
            or ref.type == 'getlocal' then
                results[#results+1] = ref
            end
        end
        ::CONTINUE::
    end
    return results
end

local function stepRefOfDocType(status, obj, mode)
    local results = {}
    if obj.type == 'doc.class.name'
    or obj.type == 'doc.type.name'
    or obj.type == 'doc.alias.name'
    or obj.type == 'doc.extends.name'
    or obj.type == 'doc.see.name' then
        local name = obj[1]
        if not name or not status.interface.docType then
            return results
        end
        if name == 'nil'
        or name == 'any'
        or name == 'boolean'
        or name == 'string'
        or name == 'table'
        or name == 'number'
        or name == 'integer'
        or name == 'function'
        or name == 'table'
        or name == 'thread'
        or name == 'userdata'
        or name == 'lightuserdata' then
            mode = 'def'
        end
        local docs = status.interface.docType(name)
        for i = 1, #docs do
            local doc = docs[i]
            if mode == 'def' then
                if doc.type == 'doc.class.name'
                or doc.type == 'doc.alias.name' then
                    results[#results+1] = doc
                end
            else
                results[#results+1] = doc
            end
        end
    else
        results[#results+1] = obj
    end
    if obj.type == "doc.type.name" then
        if rbxlibs.object[obj[1]] then
            results[#results+1] = makeNameType(obj[1])
        end
    end
    return results
end

function m.getStepRef(status, obj, mode)
    if obj.type == 'getlocal'
    or obj.type == 'setlocal' then
        return stepRefOfLocal(status, obj, obj.node, mode)
    end
    if obj.type == 'local' then
        return stepRefOfLocal(status, nil, obj, mode)
    end
    if obj.type == 'doc.class.name'
    or obj.type == 'doc.type.name'
    or obj.type == 'doc.extends.name'
    or obj.type == 'doc.alias.name' then
        return stepRefOfDocType(status, obj, mode)
    end
    if obj.type == 'function' then
        return { obj }
    end
    return nil
end

-- 根据语法，单步搜索field
local function stepFieldOfLocal(loc)
    local results = {}
    local refs = loc.ref
    for i = 1, #refs do
        local ref = refs[i]
        if ref.type == 'setglobal'
        or ref.type == 'getglobal' then
            results[#results+1] = ref
        elseif ref.type == 'getlocal' then
            local nxt = ref.next
            if nxt then
                if nxt.type == 'setfield'
                or nxt.type == 'getfield'
                or nxt.type == 'setmethod'
                or nxt.type == 'getmethod'
                or nxt.type == 'setindex'
                or nxt.type == 'getindex' then
                    results[#results+1] = nxt
                end
            end
        end
    end
    return results
end
local function stepFieldOfTable(tbl)
    local result = {}
    for i = 1, #tbl do
        result[i] = tbl[i]
    end
    return result
end
function m.getStepField(obj)
    if obj.type == 'getlocal'
    or obj.type == 'setlocal' then
        return stepFieldOfLocal(obj.node)
    end
    if obj.type == 'local' then
        return stepFieldOfLocal(obj)
    end
    if obj.type == 'table' then
        return stepFieldOfTable(obj)
    end
end

local function convertSimpleList(list)
    local simple = {}
    for i = #list, 1, -1 do
        local c = list[i]
        if     c.type == 'getglobal'
        or     c.type == 'setglobal' then
            if c.special == '_G' then
                simple.mode = 'global'
                goto CONTINUE
            end
            local loc = c.node
            if loc.special == '_G' then
                simple.mode = 'global'
                if not simple.node then
                    simple.node = c
                end
            else
                simple.mode = 'local'
                simple[#simple+1] = m.getSimpleName(loc)
                if not simple.node then
                    simple.node = loc
                end
            end
        elseif c.type == 'getlocal'
        or     c.type == 'setlocal' then
            if c.special == '_G' then
                simple.mode = 'global'
                goto CONTINUE
            end
            simple.mode = 'local'
            if not simple.node then
                simple.node = c--.node
            end
        elseif c.type == 'local' then
            simple.mode = 'local'
            if not simple.node then
                simple.node = c
            end
        else
            if not simple.node then
                simple.node = c
            end
        end
        simple[#simple+1] = m.getSimpleName(c) or m.ANY
        ::CONTINUE::
    end
    if simple.mode == 'global' and #simple == 0 then
        simple[1] = '_G'
        simple.node = list[#list]
    end
    return simple
end

-- 搜索 `a.b.c` 的等价表达式
local function buildSimpleList(obj, max)
    local list = {}
    local cur = obj
    if obj.type == "type.typeof" then
        cur = obj.value
    end
    local limit = max and (max + 1) or 11
    for i = 1, max or limit do
        if i == limit then
            return nil
        end
        while cur.type == 'paren' do
            cur = cur.exp
            if not cur then
                return nil
            end
        end
        if cur.type == 'setfield'
        or cur.type == 'getfield'
        or cur.type == 'setmethod'
        or cur.type == 'getmethod'
        or cur.type == 'setindex'
        or cur.type == 'getindex' then
            list[i] = cur
            cur = cur.node
        elseif cur.type == 'tablefield'
        or     cur.type == 'tableindex' then
            list[i] = cur
            cur = cur.parent.parent
            if cur.type == 'return' then
                list[i+1] = list[i].parent
                break
            end
        elseif cur.type == 'getlocal'
        or     cur.type == 'setlocal'
        or     cur.type == 'local' then
            list[i] = cur
            break
        elseif cur.type == 'setglobal'
        or     cur.type == 'getglobal' then
            list[i] = cur
            break
        elseif cur.type == 'select'
        or     cur.type == 'table'
        or     cur.type == 'call' then
            list[i] = cur
            break
        elseif cur.type == 'string' then
            list[i] = cur
            break
        elseif cur.type == 'number' then
            list[i] = cur
            break
        elseif cur.type == '...' then
            list[i] = cur
            break
        elseif cur.type == 'doc.class.name'
        or     cur.type == 'doc.type.name'
        or     cur.type == 'doc.class'
        or     cur.type == 'doc.see.name' then
            list[i] = cur
            break
        elseif cur.type == 'doc.see.field' then
            list[i] = cur
            cur = cur.parent.name
        elseif cur.type == 'function'
        or     cur.type == 'main' then
            break
        elseif cur.type == "binary"
        or     cur.type == "unary" then
            list[i] = cur
            break
        elseif cur.type == "ifexp"
        or     cur.type == "elseifexp" then
            list[i] = cur
            break
        elseif cur.type == "type.assert" then
            list[i] = cur
            break
        elseif cur.type == 'type.field'
        or     cur.type == 'type.index'
        or     cur.type == 'type.library' then
            list[i] = cur
            break
        else
            return nil
        end
    end
    return convertSimpleList(list)
end

function m.getSimple(obj, max)
    local simpleList
    if obj.type == 'getfield'
    or obj.type == 'setfield'
    or obj.type == 'getmethod'
    or obj.type == 'setmethod'
    or obj.type == 'getindex'
    or obj.type == 'setindex'
    or obj.type == 'local'
    or obj.type == 'getlocal'
    or obj.type == 'setlocal'
    or obj.type == 'setglobal'
    or obj.type == 'getglobal'
    or obj.type == 'tablefield'
    or obj.type == 'tableindex'
    or obj.type == 'select'
    or obj.type == 'call'
    or obj.type == 'table'
    or obj.type == 'string'
    or obj.type == 'number'
    or obj.type == '...'
    or obj.type == 'binary'
    or obj.type == 'unary'
    or obj.type == 'ifexp'
    or obj.type == 'elseifexp'
    or obj.type == 'doc.class.name'
    or obj.type == 'doc.class'
    or obj.type == 'doc.type.name'
    or obj.type == 'doc.see.name'
    or obj.type == 'doc.see.field'
    or obj.type == 'type.typeof'
    or obj.type == 'type.field'
    or obj.type == 'type.index'
    or obj.type == 'type.library'
    or obj.type == 'type.assert' then
        simpleList = buildSimpleList(obj, max)
    elseif obj.type == 'field'
    or     obj.type == 'method' then
        simpleList = buildSimpleList(obj.parent, max)
    end
    return simpleList
end

function m.getVisibleRefs(obj, status)
    if not obj.ref then
        return nil
    end
    if not status.main then
        return obj.ref
    end
    local searchFrom = status.searchFrom or status.main
    local root = m.getRoot(obj)
    if root ~= m.getRoot(searchFrom) then
        if root.returns then
            searchFrom = root.returns[#root.returns]
        else
            return obj.ref
        end
    end
    local refs = {}
    local mainFunc = m.getParentFunction(searchFrom) or searchFrom
    local range = select(2, m.getRange(searchFrom))
    local hasTypeAnn = obj.typeAnn
    for _, ref in ipairs(obj.ref) do
        if ref ~= status.main then
            if hasTypeAnn and m.isSet(ref) then
                goto CONTINUE
            end
            local refFunc = m.getParentFunction(ref)
            local mainFunc, range = mainFunc, range
            if status.funcMain[refFunc] and refFunc ~= mainFunc then
                mainFunc = refFunc
                range = select(2, m.getRange(status.funcMain[refFunc]))
            end
            if refFunc == mainFunc then
                if (ref.range or ref.start) > range and not (blockTypes[searchFrom.type] and not m.hasParent(searchFrom, ref)) then
                    goto CONTINUE
                end
            elseif not m.hasParent(mainFunc, refFunc) then
                goto CONTINUE
            end
        end
        refs[#refs+1] = ref
        ::CONTINUE::
    end
    return refs
end

function m.isOpaqued(loc, nodeRef, status)
    if loc.typeAnn then
        return false
    end
    if not status.main or not loc.ref then
        return false
    end
    local searchFrom = status.searchFrom or status.main
    local mainFunc = m.getParentFunction(searchFrom)
    for _, ref in ipairs(loc.ref) do
        if ref ~= status.main
        and m.isSet(ref)
        and (ref.range or ref.start) < searchFrom.start
        and (not nodeRef or not m.hasParent(nodeRef, ref))
        and m.hasParent(searchFrom, m.getParentBlock(ref)) then
            local refFunc = m.getParentFunction(ref)
            if refFunc == mainFunc or m.hasParent(mainFunc, refFunc) then
                return true
            end
        end
    end
end

function m.selectClosestsRefs(status, mode)
    local results = status.results
    if mode == "def" then
        local visibleSets = util.shallowCopy(status.sets)
        for set in pairs(status.sets) do
            local block = m.getParentBlock(set)
            local isParent = m.hasParent(status.searchFrom or status.main, block)
            for other in pairs(visibleSets) do
                if set.start > other.start and (isParent or m.hasParent(other, block)) then
                    visibleSets[other] = nil
                end
            end
        end
        for i = #results, 1, -1 do
            local ref = results[i]
            if ref.type == "metatable" then
                goto CONTINUE
            end
            local hasSet = false
            for set, values in pairs(status.sets) do
                for _, value in ipairs(values) do
                    if value == ref then
                        if visibleSets[set] then
                            goto CONTINUE
                        end
                        hasSet = true
                    end
                end
            end
            if hasSet then
                results[i] = results[#results]
                results[#results] = nil
            end
            ::CONTINUE::
        end
    elseif mode == "field" then
        for i = 1, #results do
            local ref = results[i]
            if ref and m.isSet(ref) then
                local key = m.getKeyName(ref)
                if key and m.getKeyType(ref) == "string" then
                    local block = m.getParentBlock(ref)
                    local isParent = m.hasParent(status.searchFrom or status.main, block)
                    for j = #results, 1, -1 do
                        local other = results[j]
                        if  other
                        and m.isSet(other)
                        and m.getKeyName(other) == key
                        and m.getKeyType(other) == "string" then
                            if ref.start > other.start and (isParent or m.hasParent(other, block)) then
                                results[j] = results[#results]
                                results[#results] = nil
                            end
                        end
                    end
                end
            end
        end
    end
end

---Create a new status
---@param parentStatus core.guide.status
---@param interface    table
---@param deep         boolean
---@return core.guide.status
function m.status(parentStatus, main, interface, deep, options)
    ---@class core.guide.status
    local status = {
        share      = parentStatus and parentStatus.share       or {
            count = 0,
            cacheLock = {},
        },
        main       = main          or parentStatus            and parentStatus.main,
        searchFrom = parentStatus and parentStatus.searchFrom  or options and options.searchFrom,
        funcMain   = parentStatus and parentStatus.funcMain    or {},
        depth      = parentStatus and (parentStatus.depth + 1) or 0,
        searchDeep = parentStatus and parentStatus.searchDeep  or deep or -999,
        interface  = parentStatus and parentStatus.interface   or {},
        deep       = parentStatus and parentStatus.deep,
        clock      = parentStatus and parentStatus.clock       or osClock(),
        options    = parentStatus and parentStatus.options     or options or {},
        results    = {},
        sets       = {},
    }
    if config.config.typeChecking.mode == "Disabled" then
        status.options.searchAll = true
        status.options.onlyDef = false
    end
    if status.options.searchAll then
        status.main = nil
    end
    if interface then
        for k, v in pairs(interface) do
            status.interface[k] = v
        end
    end
    status.deep = status.depth <= status.searchDeep
    return status
end

function m.copyStatusResults(a, b)
    local ra = a.results
    local rb = b.results
    for i = 1, #rb do
        ra[#ra+1] = rb[i]
    end
end

function m.isGlobal(source)
    if source.type == 'setglobal'
    or source.type == 'getglobal' then
        if source.node and source.node.tag == '_ENV' then
            return true
        end
    end
    if source.type == 'field' then
        source = source.parent
    end
    if source.type == 'getfield'
    or source.type == 'setfield' then
        local node = source.node
        if node and node.special == '_G' then
            return true
        end
    end
    return false
end

function m.isDoc(source)
    return source.type:sub(1, 4) == 'doc.'
end

function m.isDocClass(source)
    return source.type == 'doc.class'
end

function m.isSet(source)
    local tp = source.type
    if tp == 'setglobal'
    or tp == 'local'
    or tp == 'setlocal'
    or tp == 'setfield'
    or tp == 'setmethod'
    or tp == 'setindex'
    or tp == 'tablefield'
    or tp == 'tableindex' then
        return true
    end
    if tp == 'call' then
        local special = m.getSpecial(source.node)
        if special == 'rawset' then
            return true
        end
    end
    return false
end

function m.isGet(source)
    local tp = source.type
    if tp == 'getglobal'
    or tp == 'getlocal'
    or tp == 'getfield'
    or tp == 'getmethod'
    or tp == 'getindex' then
        return true
    end
    if tp == 'call' then
        local special = m.getSpecial(source.node)
        if special == 'rawget' then
            return true
        end
    end
    return false
end

function m.getSpecial(source)
    if not source then
        return nil
    end
    return source.special
end

--- 根据函数的调用参数，获取：调用，参数索引
function m.getCallAndArgIndex(callarg)
    local callargs = callarg.parent
    if not callargs or callargs.type ~= 'callargs' then
        return nil
    end
    local index
    for i = 1, #callargs do
        if callargs[i] == callarg then
            index = i
            break
        end
    end
    local call = callargs.parent
    return call, index
end

--- 根据函数调用的返回值，获取：调用的函数，参数列表，自己是第几个返回值
function m.getCallValue(source)
    local value = m.getObjectValue(source) or source
    if not value then
        return
    end
    local call, index
    if value.type == 'call' then
        call  = value
        index = 1
    elseif value.type == 'select' then
        call  = value.vararg
        index = value.index
        if call.type ~= 'call' then
            return
        end
    else
        return
    end
    if index > 1 and call.pcallArgs then
        return call.args[1], call.pcallArgs, index - 1
    end
    return call.node, call.args, index
end

function m.getNextRef(ref)
    local nextRef = ref.next
    if nextRef then
        if nextRef.type == 'setfield'
        or nextRef.type == 'getfield'
        or nextRef.type == 'setmethod'
        or nextRef.type == 'getmethod'
        or nextRef.type == 'setindex'
        or nextRef.type == 'getindex' then
            return nextRef
        end
    end
    -- 穿透 rawget 与 rawset
    local call, index = m.getCallAndArgIndex(ref)
    if call then
        if call.node.special == 'rawset' and index == 1 then
            return call
        end
        if call.node.special == 'rawget' and index == 1 then
            return call
        end
    end

    return nil
end

function m.checkSameSimpleInValueOfTable(status, value, start, pushQueue)
    if value.type ~= 'table' then
        return
    end
    for i = 1, #value do
        local field = value[i]
        pushQueue(field, start + 1)
    end
end

function m.checkStatusDepth(status)
    if status.depth <= 20 then
        return true
    end
    if m.debugMode then
        error('status.depth overflow')
    elseif DEVELOP then
        --log.warn(debug.traceback('status.depth overflow'))
        logWarn('status.depth overflow')
    end
    return false
end

function m.searchMeta(status, obj)
    if not obj then
        return
    end
    while obj.type == 'paren' do
        obj = obj.exp
        if not obj then
            return nil
        end
    end
    if m.isLiteral(obj) then
        if rbxlibs.object[obj.type].meta then
            for _, method in ipairs(rbxlibs.object[obj.type].meta.value) do
                status.results[#status.results+1] = method
            end
        end
        return
    end
    local cache, makeCache = m.getRefCache(status, obj, "meta")
    if cache then
        for i = 1, #cache do
            status.results[#status.results+1] = cache[i]
        end
        return
    end
    local simple = m.getSimple(obj)
    if not simple then
        return
    end
    local newStatus = m.status(status)
    m.searchSameFields(newStatus, simple, "meta")
    m.cleanResults(newStatus.results)
    for _, meta in ipairs(newStatus.results) do
        if meta.type == "metatable" then
            m.searchFields(status, meta.value, nil, "deffield")
        end
    end
    if makeCache then
        makeCache(status.results)
    end
end

function m.searchFields(status, obj, key, mode)
    if not m.checkStatusDepth(status) then
        return
    end
    if m.isTypeAnn(obj) then
        obj = m.getFullType(status, obj) or obj
        if obj.type == "type.table" then
            for _, field in ipairs(obj) do
                status.results[#status.results+1] = field
            end
        end
    end
    local simple = m.getSimple(obj)
    if not simple then
        return
    end
    simple[#simple+1] = key or m.ANY
    m.searchSameFields(status, simple, mode)
    m.cleanResults(status.results)
    if status.main and not status.options.searchAll then
        m.selectClosestsRefs(status, "field")
    end
end

---@param obj parser.guide.object
---@return parser.guide.object
function m.getObjectValue(obj)
    local paren = false
    while obj.type == 'paren' do
        paren = true
        obj = obj.exp
        if not obj then
            return nil
        end
    end
    if obj.type == "type.field"
    or obj.type == "type.index"
    or obj.type == "type.library" then
        return obj.value
    end
    if obj.type == "type.field.key" then
        return obj.parent and obj.parent.value
    end
    if obj.type == 'boolean'
    or obj.type == 'number'
    or obj.type == 'integer'
    or obj.type == 'string'
    or obj.type == 'doc.type.table'
    or obj.type == 'doc.type.array'
    or obj.type == "metatable"
    or m.typeAnnTypes[obj.type] then
        return obj
    end
    if obj.value then
        return obj.value
    end
    if obj.type == 'field'
    or obj.type == 'method' then
        return obj.parent and obj.parent.value
    end
    if obj.type == 'call' then
        if obj.node.special == 'rawset' then
            return obj.args and obj.args[3]
        else
            return obj
        end
    end
    if obj.type == 'select' then
        return obj
    end
    if paren then
        return obj
    end
    return nil
end

function m.checkSameSimpleInValueInMetaTable(status, mt, start, pushQueue)
    if status.options.skipMeta then
        return
    end
    if not status.share.metaCache then
        status.share.metaCache = {}
    end
    if not status.share.metaCache[mt] then
        status.share.metaCache[mt] = {
            type = "metatable",
            value = mt
        }
    end
    pushQueue(status.share.metaCache[mt], start, true)
    -- local newStatus = m.status(status, mt)
    -- m.searchRefs(newStatus, mt, "def")
    -- for _, def in ipairs(newStatus.results) do
    --     if not status.share.metaCache[def] then
    --         status.share.metaCache[def] = {
    --             type = "metatable",
    --             value = def
    --         }
    --     end
    --     pushQueue(status.share.metaCache[def], start, true)
    -- end
end
function m.checkSameSimpleInValueOfSetMetaTable(status, func, start, pushQueue)
    if not func or func.special ~= 'setmetatable' then
        return
    end
    local call = func.parent
    local args = call.args
    if not args then
        return
    end
    local obj = args[1]
    local mt = args[2]
    if obj then
        -- pushQueue(obj, start, true)
        -- local newStatus = m.status(status)
        -- m.searchRefs(newStatus, obj, 'def')
        -- for _, def in ipairs(newStatus.results) do
        --     pushQueue(def, start, true)
        -- end
    end
    if mt then
        if not status.share.markMetaTable then
            status.share.markMetaTable = {}
        end
        if status.share.markMetaTable[mt] then
            return
        end
        status.share.markMetaTable[mt] = true
        m.checkSameSimpleInValueInMetaTable(status, mt, start, pushQueue)
        status.share.markMetaTable[mt] = nil
    end
end

function m.checkSameSimpleInValueOfCallMetaTable(status, call, start, pushQueue)
    if status.crossMetaTableMark then
        return
    end
    status.crossMetaTableMark = true
    if call.type == 'call' then
        m.checkSameSimpleInValueOfSetMetaTable(status, call.node, start, pushQueue)
    end
    status.crossMetaTableMark = false
end

function m.checkSameSimpleInParamSelf(status, obj, start, pushQueue)
    if obj.type ~= 'getlocal' or obj[1] ~= 'self' then
        return
    end
    local node = obj.node
    if node.tag == 'self' then
        return
    end
    if node.parent.type ~= 'funcargs' then
        return
    end
    local func = node.parent.parent
    if func.type ~= 'function'
    or func.parent.type ~= 'setfield'
    or func.parent.type ~= 'setmethod' then
        return
    end
    local fieldNode = func.parent.node
    local newStatus = m.status(status)
    m.searchRefs(newStatus, fieldNode, 'ref')
    for _, ref in ipairs(newStatus.results) do
        pushQueue(ref, start, true)
    end
end

function m.getFuncArgIndex(funcargs, obj)
    for i, v in ipairs(funcargs) do
        if v == obj then
            return i
        end
    end
end

local function pushCallbackArgs(source, argIndex, status, start, pushQueue)
    source = m.getFullType(status, source)
    local overloads = {}
    if source.type == "type.function" then
        overloads[#overloads+1] = source
    elseif source.type == "type.union" or source.type == "type.inter" then
        for _, value in ipairs(m.getAllValuesInType(source)) do
            value = m.getFullType(status, value)
            if value.type == "type.function" then
                overloads[#overloads+1] = value
            end
        end
    end
    for _, callback in ipairs(overloads) do
        if #callback.args > 0 then
            local arg = callback.args[argIndex]
            if not arg then
                if callback.args[#callback.args].type == "type.variadic" then
                    arg = callback.args[#callback.args]
                end
            end
            if arg then
                pushQueue(arg.type == "type.variadic" and arg.value or arg, start, true)
            end
        end
    end
end

function m.checkSameSimpleInCallbackParam(status, obj, start, pushQueue)
    if obj.type ~= "local" or obj.typeAnn then
        return
    end
    if not obj.parent or obj.parent.type ~= 'funcargs' then
        return
    end
    local argIndex = m.getFuncArgIndex(obj.parent, obj)
    if not argIndex then
        return
    end
    local func = obj.parent.parent
    if func.parent.type == "callargs" then
        local callbackIndex = m.getFuncArgIndex(func.parent, func)
        if callbackIndex then
            local newStatus = m.status(status)
            m.searchRefs(newStatus, func.parent.parent.node, 'def')
            for _, src in ipairs(newStatus.results) do
                if m.isTypeAnn(src) then
                    src = m.getFullType(status, src)
                end
                if src.type == "type.function" or src.type == "function" then
                    local callback = src.args[callbackIndex]
                    if callback then
                        if callback.typeAnn then
                            callback = callback.typeAnn.value
                        end
                        pushCallbackArgs(callback, argIndex, status, start, pushQueue)
                    end
                end
            end
        end
    elseif m.isSet(func.parent) then
        local newStatus = m.status(status)
        m.searchRefs(newStatus, func.parent, 'def')
        for _, src in ipairs(newStatus.results) do
            if src ~= func then
                pushCallbackArgs(src, argIndex, status, start, pushQueue)
            end
        end
    end
end

local function appendValidGenericType(results, status, typeName, obj)
    if typeName.parent.type == 'doc.type.typeliteral' then
        if obj.type == 'string' and status.interface.docType then
            local docs = status.interface.docType(obj[1])
            for i = 1, #docs do
                local doc = docs[i]
                if doc.type == 'doc.class.name'
                or doc.type == 'doc.alias.name' then
                    results[#results+1] = doc
                    break
                end
            end
        end
    else
        -- 发现没有使用 `T`，则沿用既有逻辑直接返回实参
        results[#results+1] = obj
    end
end

local function stepRefOfGenericCrossTable(status, doc, typeName)
    for _, typeUnit in ipairs(doc.extends.types) do
        if typeUnit.type == 'doc.type.table' then
            for _, where in ipairs {'key', 'value'} do
                local childTypes = typeUnit[where].types
                for _, childName in ipairs(childTypes) do
                    if childName[1] == typeName[1] then
                        return function (obj)
                            local childStatus = m.status(status)
                            m.searchRefs(childStatus, obj, 'def')
                            for _, res in ipairs(childStatus.results) do
                                if res.type == 'doc.type.table' then
                                    return res[where]
                                end
                                if res.type == 'doc.type.array' then
                                    if where == 'key' then
                                        return status.interface and status.interface.docType('integer')[1]
                                    end
                                    if where == 'value' then
                                        return res.node
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return function (obj)
                return nil
            end
        elseif typeUnit.type == 'doc.type.array' then
            return function (obj)
                local childStatus = m.status(status)
                m.searchRefs(childStatus, obj, 'def')
                for _, res in ipairs(childStatus.results) do
                    if res.type == 'doc.type.array' then
                        return res.node
                    end
                end
            end
        end
    end
    return nil
end

local function getIteratorArg(status, args, index)
    local call = args.parent
    local node = call.node
    if not node.iterator then
        return nil
    end
    if node.type ~= 'call' then
        return nil
    end
    local results = m.checkSameSimpleInCallInSameFile(status, node.node, node.args, index + 1)
    return results[1]
end

local function stepRefOfGeneric(status, typeUnit, args, mode)
    local results = {}
    if not args then
        return results
    end
    local myName = typeUnit[1]
    for _, typeName in ipairs(typeUnit.typeGeneric[myName]) do
        if typeName == typeUnit then
            goto CONTINUE
        end
        local docArg = m.getParentType(typeName, 'doc.type.arg')
                   or  m.getParentType(typeName, 'doc.param')
                   or  m.getParentType(typeName, 'doc.type.array')
        if not docArg then
            goto CONTINUE
        end
        local doc = m.getDocState(docArg)
        if not doc.bindSources then
            goto CONTINUE
        end
        local crossTable = stepRefOfGenericCrossTable(status, docArg, typeName)

        -- find out param index
        local genericIndex
        if docArg.type == 'doc.param' then
            local paramName = docArg.param[1]
            for _, source in ipairs(doc.bindSources) do
                if  source.type == 'function'
                and source.args then
                    for i, arg in ipairs(source.args) do
                        if arg[1] == paramName then
                            genericIndex = i
                            break
                        end
                    end
                end
            end
        elseif docArg.type == 'doc.type.arg' then
            for index, arg in ipairs(docArg.parent.args) do
                if arg == docArg then
                    genericIndex = index
                    break
                end
            end
        end

        local callArg = args[genericIndex]
                    or  getIteratorArg(status, args, genericIndex)

        if not callArg then
            goto CONTINUE
        end
        if crossTable then
            callArg = crossTable(callArg)
            if not callArg then
                goto CONTINUE
            end
        end
        appendValidGenericType(results, status, typeName, callArg)
        ::CONTINUE::
    end
    return results
end

function m.checkSameSimpleByDocType(status, doc, args)
    if status.share.searchingBindedDoc then
        return
    end
    if doc.type ~= 'doc.type' then
        return
    end
    local results = {}
    for _, piece in ipairs(doc.types) do
        if piece.typeGeneric then
            local pieceResult = stepRefOfGeneric(status, piece, args, 'def')
            for _, res in ipairs(pieceResult) do
                results[#results+1] = res
            end
        else
            local pieceResult = stepRefOfDocType(status, piece, 'def')
            for _, res in ipairs(pieceResult) do
                results[#results+1] = res
            end
        end
    end
    return results
end

function m.checkSameSimpleByBindDocs(status, obj, start, pushQueue, mode)
    if status.options.skipDoc then
        return false
    end
    if not obj.bindDocs then
        return
    end
    if status.share.searchingBindedDoc then
        return
    end
    local skipInfer = false
    local results = {}
    for _, doc in ipairs(obj.bindDocs) do
        if     doc.type == 'doc.class' then
            results[#results+1] = doc
        elseif doc.type == 'doc.type' then
            results[#results+1] = doc
        elseif doc.type == 'doc.param' then
            -- function (x) 的情况
            if  obj.type == 'local'
            and m.getKeyName(obj) == doc.param[1] then
                if obj.parent.type == 'funcargs'
                or obj.parent.type == 'in'
                or obj.parent.type == 'loop' then
                    results[#results+1] = doc.extends
                end
            end
        elseif doc.type == 'doc.field' then
            results[#results+1] = doc
        elseif doc.type == 'doc.vararg' then
            if obj.type == '...' then
                results[#results+1] = doc
            end
        elseif doc.type == 'doc.overload' then
            results[#results+1] = doc.overload
        elseif doc.type == 'doc.module' then
            results[#results+1] = doc
        end
    end
    for _, res in ipairs(results) do
        if res.type == 'doc.class'
        or res.type == 'doc.type'
        or res.type == 'doc.vararg'
        or res.type == 'doc.module' then
            pushQueue(res, start, true)
            skipInfer = true
        end
        if res.type == 'doc.type.function' then
            pushQueue(res, start, true)
        elseif res.type == 'doc.field' then
            pushQueue(res, start + 1)
        end
    end
    return skipInfer
end

function m.checkSameSimpleOfRefByDocSource(status, obj, start, pushQueue, mode)
    if status.share.searchingBindedDoc then
        return
    end
    if not obj.bindSources then
        return
    end
    status.share.searchingBindedDoc = true
    local mark = {}
    local newStatus = m.status(status)
    for _, ref in ipairs(obj.bindSources) do
        if not mark[ref] then
            mark[ref] = true
            m.searchRefs(newStatus, ref, mode)
        end
    end
    status.share.searchingBindedDoc = nil
    for _, res in ipairs(newStatus.results) do
        pushQueue(res, start, true)
    end
end

function m.checkSameSimpleOfRefByDocReturn(status, obj, start, pushQueue, mode)
    if status.share.searchingBindedDoc then
        return
    end
    if not obj.bindSources then
        return
    end
    local index = 0
    for _, doc in ipairs(obj.bindGroup) do
        if doc.type == 'doc.return' then
            index = index + 1
            if doc == obj then
                break
            end
        end
    end
    status.share.searchingBindedDoc = true
    local mark = {}
    local newStatus = m.status(status)
    for _, ref in ipairs(obj.bindSources) do
        if not mark[ref] then
            mark[ref] = true
            m.searchRefs(newStatus, ref, mode)
        end
    end
    status.share.searchingBindedDoc = nil
    for _, res in ipairs(newStatus.results) do
        if res.type == 'metatable' then
            pushQueue(res, start, true)
        else
            local call = res.parent
            if call.type == 'call' then
                if index == 1 then
                    local sel = call.parent
                    if sel.type == 'select' and sel.index == index then
                        pushQueue(sel.parent, start, true)
                    end
                else
                    if call.extParent then
                        for _, sel in ipairs(call.extParent) do
                            if sel.type == 'select' and sel.index == index then
                                pushQueue(sel.parent, start, true)
                            end
                        end
                    end
                end
            end
        end
    end
end

function m.copyTypeWithGenerics(obj, generics, mark)
    mark = mark or {}
    if mark[obj] then
        return mark[obj]
    end
    if obj.type == "type.name" and generics.replace[obj[1]] then
        local copy = util.shallowCopy(generics.replace[obj[1]])
        copy.original = obj
        copy.paramName = obj.paramName
        copy.optional = copy.optional or obj.optional
        copy.readOnly = copy.readOnly or obj.readOnly
        mark[obj] = copy
        return copy
    end
    local copy = {}
    copy.original = obj
    mark[obj] = copy
    local childMap = m.childMap[obj.type]
    for index, value in pairs(obj) do
        if mark[value] then
            copy[index] = mark[value]
            goto CONTINUE
        end
        local key = type(index) == "number" and "#" or index
        if childMap and util.tableHas(childMap, key) then
            for _, source in ipairs(generics.sources) do
                if value == source or m.hasParent(source, value) then
                    copy[index] = m.copyTypeWithGenerics(value, generics, mark)
                    mark[value] = copy[index]
                    goto CONTINUE
                end
            end
        end
        copy[index] = value
        ::CONTINUE::
    end
    return copy
end

function m.getGenericsReplace(typeAlias, generics)
    local replace = {
        sources = {},
        replace = {}
    }
    for index, value in ipairs(generics) do
        local generic = typeAlias.generics[index]
        if generic then
            for _, source in ipairs(generic.replace) do
                replace.sources[#replace.sources+1] = source
            end
            replace.replace[generic[1]] = value
        end
    end
    return replace
end

function m.eachChildOfLibrary(obj, callback)
    local checked = {}
    if obj.child then
        for _, child in pairs(obj.child) do
            local ret = callback(child)
            if ret then
                return ret
            end
            checked[child.name] = true
        end
    end
    local libObject = rbxlibs.object[obj[1]]
    if libObject then
        if libObject.ref then
            for _, child in pairs(libObject.ref) do
                if not checked[child.name] then
                    local ret = callback(child)
                    if ret then
                        return ret
                    end
                    checked[child.name] = true
                end
            end
        end
        for _, child in pairs(libObject.child) do
            if not checked[child.name] then
                local ret = callback(child)
                if ret then
                    return ret
                end
            end
        end
        if config.config.typeChecking.options["infer-instance-from-unknown"] then
            local index
            if obj[1] == "Instance" then
                index = util.shallowCopy(rbxlibs.instanceOrAnyIndex)
            elseif rbxlibs.ClassNames[obj[1]] then
                index = util.shallowCopy(rbxlibs.instanceIndex)
            end
            if index then
                index.parent = obj
                callback(index)
            end
        end
    end
end

function m.checkSameSimpleByTypeAnn(status, obj, start, pushQueue, mode)
    if obj.typeAnn then
        if status.options.skipType then
            return false
        end
        pushQueue(obj.typeAnn.value, start, true)
        return true
    else
        if status.options.fullType then
            mode = "ref"
        end
        while obj.type == 'paren' do
            obj = obj.exp
            if not obj then
                return false
            end
        end
        if obj.type == "type.assert" then
            if status.options.skipType then
                pushQueue(obj[1], start, true)
            else
                pushQueue(obj[2], start, true)
            end
        elseif obj.type == "type.library" then
            pushQueue(obj.value, start, true)
        elseif obj.type == "type.name" then
            if mode ~= "def" then
                local typeAlias = m.getTypeAlias(status, obj)
                if typeAlias then
                    if obj.generics and typeAlias.generics then
                        local copy = m.copyTypeWithGenerics(typeAlias.value, m.getGenericsReplace(typeAlias, obj.generics))
                        pushQueue(copy, start, true)
                    else
                        pushQueue(typeAlias.value, start, true)
                    end
                elseif not (obj.parent and obj.parent.type == "type.module") then
                    m.eachChildOfLibrary(obj, function (child)
                        pushQueue(child, start + 1)
                    end)
                end
            end
            if mode == "meta" then
                if not (obj.parent and obj.parent.type == "type.module") then
                    local libObject = rbxlibs.object[obj[1]]
                    if libObject and libObject.meta then
                        m.pushResult(status, mode, libObject.meta)
                    end
                end
            end
        elseif obj.type == "type.module" then
            if mode ~= "def" then
                pushQueue(obj[2], start, true)
            end
        elseif obj.type == "type.table" then
            for _, field in ipairs(obj) do
                pushQueue(field, start + 1)
            end
            if mode == "meta" then
                m.pushResult(status, mode, rbxlibs.object["table"].meta)
            end
        elseif obj.type == "type.field"
        or     obj.type == "type.index" then
            pushQueue(obj.value, start, true)
        elseif obj.type == "type.inter"
        or     obj.type == "type.union" then
            if mode ~= "def" then
                for _, tp in ipairs(obj) do
                    pushQueue(tp, start, true)
                end
            end
        elseif obj.type == "type.variadic" then
            pushQueue(obj.value, start, true)
        elseif obj.type == "type.typeof" then
            if status.main then
                local searchFrom = status.searchFrom or status.main
                local root = m.getRoot(obj)
                if m.getRoot(searchFrom) ~= root and m.getParentFunction(obj) ~= root then
                    status.funcMain[m.getParentFunction(obj)] = obj
                end
            end
            pushQueue(obj.value, start, true)
        elseif obj.type == "type.meta" then
            if mode ~= "def" then
                pushQueue(obj[1], start, true)
                m.checkSameSimpleInValueInMetaTable(status, obj[2], start, pushQueue)
            end
        elseif obj.type ~= "type.function" then
            return false
        end
        return true
    end
end

local function getArrayOrTableLevel(obj)
    local level = 0
    while true do
        local parent = obj.parent
        if parent.type == 'doc.type.array' then
            level = level + 1
        elseif parent.type == 'doc.type.table' then
            if obj.type == 'doc.type' then
                level = level + 1
            -- else 只存在 obj.type == 'doc.type.name' 的情况，即 table<k,v> 中的 table，这种是不需要再增加层级的
            end
        elseif parent.type == 'doc.type' and parent.parent and parent.parent.type == 'doc.type.table' then
            level = level + 1
            parent = parent.parent
        else
            break
        end
        obj = parent
    end
    return level
end

function m.checkSameSimpleByDoc(status, obj, start, pushQueue, mode)
    if status.options.skipDoc then
        return false
    end
    if obj.type == 'doc.class.name'
    or obj.type == 'doc.class' then
        if obj.type == 'doc.class.name' then
            obj = m.getDocState(obj)
        end
        local classStart
        for _, doc in ipairs(obj.bindGroup) do
            if doc == obj then
                classStart = true
            elseif doc.type == 'doc.class' then
                classStart = false
            end
            if classStart and doc.type == 'doc.field' then
                pushQueue(doc, start + 1)
            end
        end
        m.checkSameSimpleOfRefByDocSource(status, obj, start, pushQueue, mode)
        if mode == 'ref' then
            local pieceResult = stepRefOfDocType(status, obj.class, 'ref')
            for _, res in ipairs(pieceResult) do
                pushQueue(res, start, true)
            end
            if obj.extends then
                for _, ext in ipairs(obj.extends) do
                    local pieceResult = stepRefOfDocType(status, ext, 'def')
                    for _, res in ipairs(pieceResult) do
                        pushQueue(res, start, true)
                    end
                end
            end
        end
        return true
    elseif obj.type == 'doc.type' then
        for _, piece in ipairs(obj.types) do
            local pieceResult = stepRefOfDocType(status, piece, 'def')
            for _, res in ipairs(pieceResult) do
                pushQueue(res, start, true)
            end
        end
        if mode == 'ref' then
            m.checkSameSimpleOfRefByDocSource(status, obj, start, pushQueue, mode)
        end
        return true
    elseif obj.type == 'doc.type.name'
    or     obj.type == 'doc.see.name' then
        local pieceResult = stepRefOfDocType(status, obj, 'def')
        for _, res in ipairs(pieceResult) do
            pushQueue(res, start, true)
        end

        if mode == 'ref' then
            local state = m.getDocState(obj)
            if state.type == 'doc.type' then
                m.checkSameSimpleOfRefByDocSource(status, state, start - getArrayOrTableLevel(obj), pushQueue, mode)
            end
            if state.type == 'doc.return' then
                m.checkSameSimpleOfRefByDocReturn(status, state, start - getArrayOrTableLevel(obj), pushQueue, mode)
            end
        end
        return true
    elseif obj.type == 'doc.field' then
        if  mode ~= 'field'
        and mode ~= 'deffield' then
            return m.checkSameSimpleByDoc(status, obj.extends, start, pushQueue, mode)
        end
    elseif obj.type == 'doc.type.array' then
        pushQueue(obj.node, start + 1, true)
        return true
    elseif obj.type == 'doc.type.table' then
        pushQueue(obj.node, start, true)
        pushQueue(obj.value, start + 1, true)
        return true
    elseif obj.type == 'doc.vararg' then
        pushQueue(obj.vararg, start, true)
    elseif obj.type == 'doc.module' then
        if status.interface.module then
            local returns = status.interface.module(obj)
            for _, ret in ipairs(returns) do
                if not m.checkReturnMark(status, ret) then
                    pushQueue(ret, start, true)
                end
            end
        end
        return true
    end
end

function m.checkSameSimpleInArg1OfSetMetaTable(status, obj, start, pushQueue)
    local args = obj.parent
    if not args or args.type ~= 'callargs' then
        return
    end
    local callNode = args.parent.node
    if callNode.special ~= 'setmetatable' then
        return
    end
    if args[1] ~= obj then
        return
    end
    -- if status.main then
    --     if obj == status.main or obj.start > status.main.start then
    --         return
    --     end
    -- end
    local mt = args[2]
    if mt then
        -- if m.hasValueMark(status, mt) then
        --     return
        -- end
        m.checkSameSimpleInValueInMetaTable(status, mt, start, pushQueue)
    end
end

function m.searchSameMethodOutSelf(ref, mark)
    local selfNode
    if ref.tag == 'self' then
        selfNode = ref
    else
        if ref.type == 'getlocal'
        or ref.type == 'setlocal' then
            local node = ref.node
            if node.tag == 'self' then
                selfNode = node
            end
        end
    end
    if selfNode then
        if mark[selfNode] then
            return nil
        end
        mark[selfNode] = true
        local method = selfNode.method.node
        if mark[method] then
            return nil
        end
        mark[method] = true
        return method
    end
end

function m.searchSameMethodIntoSelf(ref, mark)
    local nxt = ref.next
    if not nxt then
        return nil
    end
    if nxt.type ~= 'setmethod' then
        return nil
    end
    if mark[ref] then
        return nil
    end
    mark[ref] = true
    local value = nxt.value
    if not value or value.type ~= 'function' then
        return nil
    end
    local selfRef = value.locals and value.locals[1]
    if not selfRef or selfRef.tag ~= 'self' then
        return nil
    end
    if mark[selfRef] then
        return nil
    end
    mark[selfRef] = true
    return selfRef
end

function m.searchSameFieldsCrossMethod(status, ref, start, pushQueue, mode)
    if status.share.crossMethodMark2 then
        return
    end
    local mark = status.crossMethodMark
    if not mark then
        mark = {}
        status.crossMethodMark = mark
    end
    if mark[ref] then
        return
    end
    local selfRef = m.searchSameMethodIntoSelf(ref, mark)
    if selfRef then
        tracy.ZoneBeginN 'searchSameFieldsCrossMethod'
        local _ <close> = tracy.ZoneEnd
        -- 如果自己是method，则只检查自己内部的self引用
        status.share.inBeSetValue = (status.share.inBeSetValue or 0) + 1
        status.share.crossMethodMark2 = true
        local newStatus = m.status(status)
        m.searchRefs(newStatus, selfRef, mode)
        for _, res in ipairs(newStatus.results) do
            pushQueue(res, start, true)
        end
        status.share.inBeSetValue = (status.share.inBeSetValue or 0) - 1
        status.share.crossMethodMark2 = nil
        return
    end
    local method = m.searchSameMethodOutSelf(ref, mark)
    if method then
        if method.type == "getfield" then
            local newStatus = m.status(status)
            m.searchRefs(newStatus, method, mode)
            for _, res in ipairs(newStatus.results) do
                pushQueue(res, start, true)
            end
        end
        pushQueue(method, start, true)
        return
    end
end

local function checkSameSimpleAndMergeFunctionReturnsByDoc(status, results, source, index, args)
    if status.options.skipDoc then
        return false
    end
    source = m.getObjectValue(source) or source
    if not source or source.type ~= 'function' then
        return
    end
    if not source.bindDocs then
        return
    end
    local returns = {}
    for _, doc in ipairs(source.bindDocs) do
        if doc.type == 'doc.return' then
            for _, rtn in ipairs(doc.returns) do
                returns[#returns+1] = rtn
            end
        end
    end
    local rtn = returns[index]
    if not rtn then
        return
    end
    local types = m.checkSameSimpleByDocType(status, rtn, args)
    if not types then
        return
    end
    for _, res in ipairs(types) do
        results[#results+1] = res
    end
    return true
end

local function checkSameSimpleAndMergeDocFunctionReturn(status, results, docFunc, index, args)
    if status.options.skipDoc then
        return false
    end
    if docFunc.type ~= 'doc.type.function' then
        return
    end
    local rtn = docFunc.returns[index]
    if rtn then
        local types = m.checkSameSimpleByDocType(status, rtn, args)
        if types then
            for _, res in ipairs(types) do
                results[#results+1] = res
            end
            return true
        end
    end
end

local function checkSameSimpleAndMergeDocTypeFunctionReturns(status, results, source, index)
    if status.options.skipDoc then
        return false
    end
    if not source.bindDocs then
        return
    end
    for _, doc in ipairs(source.bindDocs) do
        if doc.type == 'doc.type' then
            for _, typeUnit in ipairs(doc.types) do
                if checkSameSimpleAndMergeDocFunctionReturn(status, results, typeUnit, index) then
                    return true
                end
            end
        end
    end
end

local function checkSameSimpleAndMergeLibrarySpecialReturns(status, results, source, index, args)
    source = m.getObjectValue(source) or source
    if not args or not source.special then
        return
    end
    if source.special == "Instance.new" then
        if index == 1 and args[1].type == "string" then
            local className = args[1][1]
            if rbxlibs.CreatableInstances[className] then
                results[#results+1] = makeNameType(className)
                return true
            end
        end
    elseif source.special == "GetService" then
        if index == 1 and args[2] and args[2].type == "string" then
            local className = args[2][1]
            if rbxlibs.Services[className] then
                results[#results+1] = makeNameType(className)
                return true
            end
        end
    elseif source.special == "FindFirstClass" then
        if index == 1 and args[2] and args[2].type == "string" then
            local className = args[2][1]
            if rbxlibs.ClassNames[className] then
                results[#results+1] = makeNameType(className)
                return true
            end
        end
    elseif source.special == "FindFirstChild" then
        if index == 1 and args[2] and args[2].type == "string" then
            local name = args[2][1]
            local parent = args[1]
            if parent then
                local newStatus = m.status(status)
                local valueMark = newStatus.share.valueMark
                newStatus.share.valueMark = nil
                m.searchRefs(newStatus, parent, "def")
                newStatus.share.valueMark = valueMark
                for _, def in ipairs(newStatus.results) do
                    def = m.getObjectValue(def) or def
                    if def.type == "type.name" then
                        local search = m.searchLibraryChildren(def)
                        for i = 1, #search do
                            for _, child in pairs(search[i]) do
                                if child.kind == "child" and child.name == name then
                                    results[#results+1] = child.value
                                    return true
                                end
                            end
                        end
                    end
                end
            end
        end
    elseif source.special == "Clone"
        or source.special == "assert"
        or source.special == "table.freeze"
        or source.special == "table.clone"
    then
        if index == 1 and args[1] then
            results[#results+1] = args[1]
            return true
        end
    elseif source.special == "setmetatable" then
        if index == 1 and args[1] then
            local newStatus = m.status(status)
            local select = m.getParentType(source, "select")
            if select then
                newStatus.searchFrom = select.parent
            else
                newStatus.searchFrom = source
            end
            m.searchRefs(newStatus, args[1], "def")
            for _, def in ipairs(newStatus.results) do
                results[#results+1] = def
            end
            return true
        end
    end
end

function m.getAllValuesInType(source, tp, results)
    results = results or {}
    for _, obj in ipairs(source) do
        while obj.type == 'paren' do
            obj = obj.exp
            if not obj then
                goto CONTINUE
            end
        end
        if obj.type == source.type then
            m.getAllValuesInType(obj, tp, results)
        else
            if tp and obj.type ~= tp then
                goto CONTINUE
            end
            results[#results+1] = obj
        end
        ::CONTINUE::
    end
    return results
end

function m.getTypeAlias(status, source)
    if source.typeAliasGeneric then
        return nil
    end
    if source.typeAlias then
        return source.typeAlias
    end
    if not source.parent then
        return nil
    end
    if source.parent.type == "type.module" then
        source = source.parent
    end
    local myUri = m.getUri(source)
    if source.type == "type.module" then
        local newStatus = m.status(status, nil, status.interface, true, {skipType = true})
        local files = require("files")
        m.searchRefs(newStatus, source[1], "def")
        for _, def in ipairs(newStatus.results) do
            local uri = m.getUri(def)
            if not files.eq(myUri, uri) then
                local ast = files.getAst(uri)
                if ast and ast.ast and ast.ast.types then
                    for _, alias in ipairs(ast.ast.types) do
                        if alias.export and source[2][1] == alias.name[1] then
                            return alias
                        end
                    end
                    break
                end
            end
        end
    else
        local files = require("files")
        if myUri and not files.isLibrary(myUri) then
            for libUri in pairs(files.libraryMap) do
                local ast = files.getAst(libUri)
                if ast and ast.ast.types then
                    for _, alias in ipairs(ast.ast.types) do
                        if alias.export and alias.name[1] == source[1] then
                            return alias
                        end
                    end
                end
            end
        end
        for _, alias in pairs(require("library.defaultlibs").customType) do
            if alias.name[1] == source[1] then
                return alias
            end
        end
    end
    return nil
end

function m.getFullType(status, tp, mark)
    mark = mark or {}
    if mark[tp] then
        return tp
    end
    mark[tp] = true
    if tp.type == "type.field"
    or tp.type == "type.index"
    or tp.type == "type.library" then
        tp = tp.value
    end
    while tp.type == "paren" do
        if not tp.exp then
            break
        end
        tp = tp.exp
    end
    -- if tp.type == "type.typeof" then
    --     local newStatus = m.status(status)
    --     m.searchRefs(newStatus, tp.value, 'def')
    --     for _, def in ipairs(newStatus.results) do
    --         if m.isTypeAnn(def) then
    --             return m.getFullType(status, def, mark)
    --         end
    --     end
    -- end
    local typeAlias = m.getTypeAlias(status, tp)
    if typeAlias then
        local generics = tp.generics
        if tp.type == "type.module" then
            generics = tp[2].generics
        end
        if generics and typeAlias.generics then
            local copy = m.copyTypeWithGenerics(typeAlias.value, m.getGenericsReplace(typeAlias, generics))
            return m.getFullType(status, copy, mark)
        else
            return m.getFullType(status, typeAlias.value, mark)
        end
    end
    return tp
end

local function typeCheckFunctionCall(status, func, callArgs)
    local typeChecker = require("core.type-checking")
    typeChecker.init()
    typeChecker.options["union-bivariance"] = true
    typeChecker.strict = true
    local varargs = nil
    local callArgCount = #callArgs
    local argChecked = 0
    for i = 1, m.getTypeCount(func.args) do
        local arg = func.args[i]
        if arg and arg.type == "type.variadic" then
            varargs = arg.value
        end
        local argType = varargs or arg
        if not argType then
            break
        end
        local other = callArgs[i]
        if not other then
            break
        end
        argChecked = argChecked + 1
        local otherType = m.getType(status, other) or makeNameType("any")
        if otherType.parent and i == callArgCount then
            if otherType.parent.type == "type.list" then
                for j = 2, #otherType.parent do
                    if otherType.parent[j].type == "type.variadic" then
                        for _ = i + j - 1, #func.args do
                            callArgs[#callArgs+1] = otherType.parent[j].value
                        end
                    else
                        if #callArgs == #func.args then
                            break
                        end
                        callArgs[#callArgs+1] = otherType.parent[j]
                    end
                end
            elseif otherType.parent.type == "type.variadic" or other.type == "varargs" then
                for _ = i + 1, #func.args do
                    callArgs[#callArgs+1] = otherType
                end
            end
        end
        if not typeChecker.compareTypes(otherType, argType) then
            typeChecker.init()
            return false
        end
    end
    typeChecker.init()
    if #callArgs > argChecked or #callArgs < typeChecker.getArgCount(func.args) then
        return false
    end
    return true
end

local function checkSameSimpleAndMergeTypeAnnReturns(status, results, source, index, args)
    if status.options.skipType then
        return false
    end
    local returns = {}
    if source.returnTypeAnn then
        returns[1] = source.returnTypeAnn.value
    elseif m.isTypeAnn(source) then
        source = m.getFullType(status, source)
        if source.type == "type.function" then
            if source.parent == rbxlibs.global["require"] then
                return true
            end
            returns[1] = source.returns
        elseif source.type == "type.inter" then
            if source.returns then
                returns[#returns+1] = source.returns
            else
                args = args or {}
                for _, func in ipairs(m.getAllValuesInType(source)) do
                    func = m.getFullType(status, func) or func
                    if func.type == "type.function" and typeCheckFunctionCall(status, func, args) then
                        returns[#returns+1] = func.returns
                        break
                    end
                end
            end
        elseif source.type == "type.typeof" then
            for _, result in ipairs(m.checkSameSimpleInCallInSameFile(status, source.value, args, index)) do
                results[#results+1] = result
            end
            return true
        end
    end
    if #returns == 0 then
        return false
    end
    for _, ret in ipairs(returns) do
        for i, tp in ipairs(ret.type == "type.list" and ret or {ret}) do
            if tp.type == "type.variadic" then
                if index >= i then
                    results[#results+1] = m.getObjectValue(tp.value)
                    break
                end
            elseif index == i then
                results[#results+1] = m.getObjectValue(tp)
                break
            end
        end
    end
    return true
end

function m.checkSameSimpleInCallInSameFile(status, func, args, index)
    if not status.share.callResultsCache then
        status.share.callResultsCache = {}
    end
    local cache = status.share.callResultsCache[func]
    if not cache then
        cache = {}
        status.share.callResultsCache[func] = cache
    end
    local results = cache[index]
    if results then
        return results
    end
    results = {}
    if checkSameSimpleAndMergeLibrarySpecialReturns(status, results, func, index, args) then
        return results
    end
    local newStatus = m.status(status)
    m.searchRefs(newStatus, func, 'def')
    local skip = false
    for _, def in ipairs(newStatus.results) do
        skip =   checkSameSimpleAndMergeDocTypeFunctionReturns(status, results, def, index)
            or   checkSameSimpleAndMergeFunctionReturnsByDoc(status, results, def, index, args)
            or   checkSameSimpleAndMergeDocFunctionReturn(status, results, def, index, args)
            or   checkSameSimpleAndMergeLibrarySpecialReturns(status, results, def, index, args)
            or   checkSameSimpleAndMergeTypeAnnReturns(status, results, def, index, args)
            or   skip
    end
    if not skip then
        for _, def in ipairs(newStatus.results) do
            local value = m.getObjectValue(def) or def
            if value.type == 'function' then
                local returns = value.returns
                if returns then
                    for _, ret in ipairs(returns) do
                        local exp = ret[index]
                        if exp then
                            results[#results+1] = exp
                        end
                    end
                end
            end
        end
    end
    cache[index] = results
    return results
end

function m.checkSameSimpleInCall(status, ref, start, pushQueue, mode)
    if status.share.inBeSetValue and status.share.inBeSetValue > 0 then
        return
    end
    if status.share.inSetValue and status.share.inSetValue > SET_VALUE_LIMIT then
        return
    end
    local func, args, index = m.getCallValue(ref)
    if not func then
        return
    end
    if func.iterator then
        return
    end
    if m.checkCallMark(status, func.parent, true) then
        return
    end
    status.share.inSetValue = (status.share.inSetValue or 0) + 1
    -- 检查赋值是 semetatable() 的情况
    -- m.checkSameSimpleInValueOfSetMetaTable(status, func, start, pushQueue)
    local objs = m.checkSameSimpleInCallInSameFile(status, func, args, index)
    if status.interface.call then
        local cobjs = status.interface.call(status, func, args, index)
        if cobjs then
            for _, obj in ipairs(cobjs) do
                if not m.checkReturnMark(status, obj) then
                    objs[#objs+1] = obj
                end
            end
        end
    end
    m.cleanResults(objs)
    if not status.share.callFuncMark then
        status.share.callFuncMark = {}
    end
    local mark = {}
    for _, obj in ipairs(objs) do
        if mark[obj] then
            goto CONTINUE
        end
        if status.share.callFuncMark[obj] then
            goto CONTINUE
        end
        status.share.callFuncMark[obj] = true
        local newStatus = m.status(status)
        if status.main then
            local parentFunc = m.getParentFunction(obj)
            if parentFunc and not m.hasParent(status.searchFrom or status.main, parentFunc) then
                -- status.funcMain[parentFunc] = obj
                -- status.searchFrom = obj
                local ret = parentFunc.returns and parentFunc.returns[#parentFunc.returns] or obj
                status.funcMain[parentFunc] = ret
                status.searchFrom = ret
            end
        end
        m.searchRefs(newStatus, obj, mode)
        pushQueue(obj, start, true)
        mark[obj] = true
        for _, obj in ipairs(newStatus.results) do
            pushQueue(obj, start, true)
            mark[obj] = true
        end
        status.share.callFuncMark[obj] = nil
        ::CONTINUE::
    end
    status.share.inSetValue = (status.share.inSetValue or 0) - 1
end

local function searchRawset(ref, results)
    if m.getKeyName(ref) ~= 'rawset' then
        return
    end
    local call = ref.parent
    if call.type ~= 'call' or call.node ~= ref then
        return
    end
    if not call.args then
        return
    end
    local arg1 = call.args[1]
    if arg1.special ~= '_G' then
        -- 不会吧不会吧，不会真的有人写成 `rawset(_G._G._G, 'xxx', value)` 吧
        return
    end
    results[#results+1] = call
end

local function searchG(ref, results)
    while ref and m.getKeyName(ref) == '_G' do
        results[#results+1] = ref
        ref = ref.next
    end
    if ref then
        results[#results+1] = ref
        searchRawset(ref, results)
    end
end

local function searchEnvRef(ref, results)
    if     ref.type == 'setglobal'
    or     ref.type == 'getglobal' then
        results[#results+1] = ref
        searchG(ref, results)
    elseif ref.type == 'getlocal' then
        results[#results+1] = ref.next
        searchG(ref.next, results)
    end
end

function m.findGlobals(ast)
    local root = m.getRoot(ast)
    local results = {}
    local env = m.getENV(root)
    if env.ref then
        for _, ref in ipairs(env.ref) do
            searchEnvRef(ref, results)
        end
    end
    return results
end

function m.findGlobalsOfName(ast, name)
    local root = m.getRoot(ast)
    local results = {}
    local globals = m.findGlobals(root)
    for _, global in ipairs(globals) do
        if m.getKeyName(global) == name then
            results[#results+1] = global
        end
    end
    return results
end

function m.checkSameSimpleInGlobal(status, source)
    local name = m.getKeyName(source)
    if not name then
        return
    end
    local objs
    if status.interface.global then
        objs = status.interface.global(name, false, m.getUri(source))
    else
        objs = m.findGlobalsOfName(source, name)
    end
    return objs
end

function m.hasValueMark(status, value)
    if not status.share.valueMark then
        status.share.valueMark = {}
    end
    if status.share.valueMark[value] then
        return true
    end
    status.share.valueMark[value] = true
    return false
end

function m.checkCallMark(status, a, mark)
    if not status.share.callMark then
        status.share.callMark = {}
    end
    if mark then
        status.share.callMark[a] = mark
    else
        return status.share.callMark[a]
    end
    return false
end

function m.checkReturnMark(status, a, mark)
    if not status.share.returnMark then
        status.share.returnMark = {}
    end
    local result = status.share.returnMark[a]
    if mark then
        status.share.returnMark[a] = mark
    end
    return result
end

function m.searchSameFieldsInValue(status, ref, start, pushQueue, mode)
    if status.share.inBeSetValue and status.share.inBeSetValue > 0 then
        return
    end
    if status.share.inSetValue and status.share.inSetValue > SET_VALUE_LIMIT then
        return
    end
    local value = m.getObjectValue(ref)
    if not value then
        return
    end
    if m.hasValueMark(status, value) then
        return
    end
    if m.isSet(ref) then
        status.currentSet = ref
    end
    status.share.inSetValue = (status.share.inSetValue or 0) + 1
    if not status.share.tempValueMark then
        status.share.tempValueMark = {}
    end
    if not status.share.tempValueMark[value] then
        status.share.tempValueMark[value] = true
        local newStatus = m.status(status)
        m.searchRefs(newStatus, value, mode)
        status.share.tempValueMark[value] = nil
        for _, res in ipairs(newStatus.results) do
            pushQueue(res, start, true)
        end
        pushQueue(value, start, true)
    end
    status.share.inSetValue = (status.share.inSetValue or 0) - 1
    -- 检查形如 a = f() 的分支情况
    -- m.checkSameSimpleInCall(status, value, start, pushQueue, mode)
end

function m.checkSameSimpleAsTableField(status, ref, start, pushQueue)
    if not status.deep then
        --return
    end
    local parent = ref.parent
    if not parent or parent.type ~= 'tablefield' then
        return
    end
    if m.hasValueMark(status, ref) then
        return
    end
    local newStatus = m.status(status)
    m.searchRefs(newStatus, parent.field, 'ref')
    for _, res in ipairs(newStatus.results) do
        pushQueue(res, start, true)
    end
end

function m.checkSearchLevel(status)
    status.share.back = status.share.back or 0
    if status.share.back >= (status.interface.searchLevel or 0) then
        -- TODO 限制向前搜索的次数
        --return true
    end
    status.share.back = status.share.back + 1
    return false
end

function m.checkSameSimpleAsReturn(status, ref, start, pushQueue)
    if not status.deep then
        return
    end
    if not ref.parent or ref.parent.type ~= 'return' then
        return
    end
    if ref.parent.parent.type ~= 'main' then
        return
    end
    if m.checkSearchLevel(status) then
        return
    end
    local newStatus = m.status(status)
    m.searchRefsAsFunctionReturn(newStatus, ref, 'ref')
    for _, res in ipairs(newStatus.results) do
        if not m.checkCallMark(status, res) then
            pushQueue(res, start, true)
        end
    end
end

function m.checkSameSimpleAsSetValue(status, ref, start, pushQueue)
    if not status.deep then
        --return
    end
    if status.share.inSetValue and status.share.inSetValue > 0 then
        return
    end
    if status.share.inBeSetValue and status.share.inBeSetValue > SET_VALUE_LIMIT then
        return
    end
    if ref.type == 'select' then
        return
    end
    local parent = ref.parent
    if not parent then
        return
    end
    if m.getObjectValue(parent) ~= ref then
        return
    end
    if m.hasValueMark(status, ref) then
        return
    end
    if m.checkSearchLevel(status) then
        return
    end
    local obj
    if     parent.type == 'local'
    or     parent.type == 'setglobal'
    or     parent.type == 'setlocal' then
        obj = parent
    elseif parent.type == 'setfield' then
        obj = parent.field
    elseif parent.type == 'setmethod' then
        obj = parent.method
    end
    if not obj then
        return
    end
    status.share.inBeSetValue = (status.share.inBeSetValue or 0) + 1
    local newStatus = m.status(status)
    m.searchRefs(newStatus, obj, 'ref')
    for _, res in ipairs(newStatus.results) do
        pushQueue(res, start, true)
    end
    status.share.inBeSetValue = (status.share.inBeSetValue or 0) - 1
end

local function getTableAndIndexIfIsForPairsKeyOrValue(ref)
    if ref.type == "select" then
        ref = ref.parent
    end

    if ref.type ~= 'local' then
        return
    end

    if not ref.parent or ref.parent.type ~= 'in' then
        return
    end

    if not ref.value or ref.value.type ~= 'select' then
        return
    end

    local rootSelectObj = ref.value
    if rootSelectObj.index ~= 1 and rootSelectObj.index ~= 2 then
        return
    end

    if not rootSelectObj.vararg or rootSelectObj.vararg.type ~= 'call' then
        return
    end
    local rootCallObj = rootSelectObj.vararg
    if not rootCallObj.node then
        return
    end

    if rootCallObj.node.special == "next" then
        local tableObj = rootCallObj.args[1]
        return tableObj, rootSelectObj.index, rootCallObj.node.special
    end

    local pairsCallObj = rootCallObj.node

    if not pairsCallObj.node or (pairsCallObj.node.special ~= 'pairs' and pairsCallObj.node.special ~= 'ipairs') then
        return rootCallObj.node, rootSelectObj.index, "pairs"
    end

    if not pairsCallObj.args or not pairsCallObj.args[1] then
        return
    end

    local tableObj = pairsCallObj.args[1]

    return tableObj, rootSelectObj.index, pairsCallObj.node.special
end

function m.checkSameSimpleAsKeyOrValueInForPairs(status, ref, start, pushQueue)
    local tableObj, index, iterator = getTableAndIndexIfIsForPairsKeyOrValue(ref)
    if not tableObj then
        return
    end
    if iterator == "ipairs" and index == 1 then
        pushQueue(makeNameType("number"), start, true)
        return
    end
    local newStatus = m.status(status)
    m.searchRefs(newStatus, tableObj, "def")
    for _, def in ipairs(newStatus.results) do
        if def.bindDocs and not status.options.skipDoc then
            for _, binddoc in ipairs(def.bindDocs) do
                if binddoc.type == 'doc.type' then
                    if binddoc.types[1] and binddoc.types[1].type == 'doc.type.table' then
                        if index == 1 then
                            pushQueue(binddoc.types[1].key, start, true)
                        elseif index == 2 then
                            pushQueue(binddoc.types[1].value, start, true)
                        end
                    end
                end
            end
        elseif m.isTypeAnn(def) then
            def = m.getFullType(status, def)
            if def.type == "type.table" then
                for _, field in ipairs(def) do
                    if field.type == "type.index" then
                        if index == 1 then
                            pushQueue(field.key, start, true)
                        elseif index == 2 then
                            pushQueue(field.value, start, true)
                        end
                        break
                    elseif field.type ~= "type.field" then
                        if index == 1 then
                            pushQueue(makeNameType("number"), start, true)
                        elseif index == 2 then
                            pushQueue(field, start, true)
                        end
                        break
                    end
                end
            end
        end
    end
end

---
---@param func parser.guide.object
---@param argIndex integer
---@return integer?
local function findGenericFromArgIndexToReturnIndex(func, argIndex)
    if not func.bindDocs then
        return nil
    end
    local paramType
    for _, doc in ipairs(func.bindDocs) do
        if doc.type == 'doc.param' then
            if doc.extends and doc.extends.paramIndex == argIndex then
                paramType = doc.extends
                break
            end
        end
    end
    if not paramType then
        return nil
    end
    for _, typeUnit in ipairs(paramType.types) do
        if typeUnit.typeGeneric then
            local generic = typeUnit.typeGeneric[typeUnit[1]]
            if generic then
                for _, typeName in ipairs(generic) do
                    local docType = typeName.parent
                    if docType.returnIndex then
                        return docType.returnIndex
                    end
                end
            end
        end
    end
    return nil
end

function m.checkSameSimpleAsCallArg(status, ref, start, pushQueue)
    if not status.deep then
        return
    end
    local call, index = m.getCallAndArgIndex(ref)
    if not call then
        return
    end
    if call.parent.type ~= 'select' then
        return
    end
    if (status.share.inSetValue or 0) > 0 then
        return
    end
    if status.share.inBeSetValue and status.share.inBeSetValue > SET_VALUE_LIMIT then
        return
    end
    status.share.inBeSetValue = (status.share.inBeSetValue or 0) + 1
    local newStatus = m.status(status)
    m.searchRefs(newStatus, call.node, 'def')
    for _, func in ipairs(newStatus.results) do
        local rindex = findGenericFromArgIndexToReturnIndex(func, index)
        if rindex then
            if rindex == 1 then
                pushQueue(call.parent.parent, start, true)
            else
                if call.extParent then
                    for _, slt in ipairs(call.extParent) do
                        if slt.index == rindex then
                            pushQueue(slt.parent, start, true)
                        end
                    end
                end
            end
        end
    end
    status.share.inBeSetValue = (status.share.inBeSetValue or 0) - 1
end

local function hasTypeName(doc, name)
    if doc.type == 'doc.type' then
        for _, tunit in ipairs(doc.types) do
            if  tunit.type == 'doc.type.name'
            and tunit[1] == name then
                return true
            end
        end
    end
    if doc.type == 'doc.type.name'
    or doc.type == 'doc.class.name' then
        if doc[1] == name then
            return true
        end
    end
    return false
end

function m.checkSameSimpleInLiteral(status, ref, start, pushQueue, mode)
    if mode == "meta" and m.isLiteral(ref) then
        local meta = rbxlibs.object[ref.type].meta
        if meta then
            status.results[#status.results+1] = meta
        end
        return true
    else
        if ref.type == 'select' then
            ref = ref.vararg
        end
        if ref.type == 'varargs' then
            if ref.typeAnn then
                pushQueue(ref.typeAnn, start, true)
            end
            return true
        elseif ref.type == "string" or hasTypeName(ref, 'string') then
            for _, child in pairs(rbxlibs.object["string"].child) do
                pushQueue(child, start + 1)
            end
            return true
        end
    end
end

function m.checkSameSimpleInMeta(status, ref, start, pushQueue, mode)
    if ref.type ~= "metatable" then
        return
    end
    if mode == "ref" then
        local cache, makeCache = m.getRefCache(status, ref.value, '__index')
        if cache then
            for _, obj in ipairs(cache) do
                pushQueue(obj, start + 1)
            end
            return
        end
        cache = {}
        local newStatus = m.status(status)
        local meta = ref.value
        if meta.type == "type.typeof" then
            if status.main then
                local searchFrom = status.searchFrom or status.main
                local root = m.getRoot(meta)
                if m.getRoot(searchFrom) ~= root and m.getParentFunction(meta) ~= root then
                    status.funcMain[m.getParentFunction(meta)] = meta
                end
            end
            meta = meta.value
        end
        m.searchFields(newStatus, meta, '__index', "deffield")
        for _, index in ipairs(newStatus.results) do
            if index.type == "tablefield" or index.type == "tableindex" then
                index = index.value
            end
            if index then
                local refsStatus = m.status(newStatus)
                m.searchFields(refsStatus, index, nil, "deffield")
                for _, field in ipairs(refsStatus.results) do
                    pushQueue(field, start + 1)
                    cache[#cache+1] = field
                end
            end
        end
        if makeCache then
            makeCache(cache)
        end
    end
    return true
end

function m.checkSameSimpleInIfExp(status, source, start, pushQueue, mode)
    source = m.getObjectValue(source) or source
    if source.type == "ifexp" or source.type == "elseifexp" then
        for i = 1, #source do
            local newStatus = m.status(status)
            m.searchRefs(newStatus, source[i], mode)
            pushQueue(source[i], start, true)
            for _, obj in ipairs(newStatus.results) do
                pushQueue(obj, start, true)
            end
        end
    end
end

function m.checkSameSimpleInBinaryOrUnary(status, source, start, pushQueue, mode)
    source = m.getObjectValue(source) or source
    if source.type == "binary" or source.type == "unary" then
        local op = source.op.type
        if op == "or" or op == "and" then
            for i = op == "and" and 2 or 1, 2 do
                local newStatus = m.status(status)
                m.searchRefs(newStatus, source[i], mode)
                pushQueue(source[i], start, true)
                for _, obj in ipairs(newStatus.results) do
                    pushQueue(obj, start, true)
                end
            end
        elseif op == "not" then
            pushQueue(makeNameType("boolean"), start, true)
        else
            if not status.share.valueMark then
                status.share.valueMark = {}
            end
            local valueMark = util.shallowCopy(status.share.valueMark)
            local tp1 = m.getType(status, source[1])
            local tp2 = m.getType(status, source[2])
            status.share.valueMark = valueMark
            local foundMeta = false
            if (tp1 and tp2) or (source.type == "unary" and tp1) then
                local newStatus = m.status(status)
                for i = 1, 2 do
                    newStatus.searchFrom = source[i]
                    m.searchMeta(newStatus, source[i])
                    for _, meta in ipairs(newStatus.results) do
                        if (source.type == "binary" and m.binaryMeta or m.unaryMeta)[op] == m.getKeyName(meta) then
                            foundMeta = true
                            local funcs = {}
                            local value = m.getObjectValue(meta)
                            if value.type == "type.function" then
                                funcs[#funcs+1] = value
                            elseif value.type == "type.inter" then
                                m.getAllValuesInType(value, nil, funcs)
                            end
                            for _, func in ipairs(funcs) do
                                func = m.getFullType(newStatus, func)
                                if func.type == "type.function" and typeCheckFunctionCall(newStatus, func, {tp1, tp2}) then
                                    local results = {}
                                    checkSameSimpleAndMergeTypeAnnReturns(newStatus, results, func, 1)
                                    for _, result in ipairs(results) do
                                        pushQueue(result, start, true)
                                    end
                                    break
                                end
                            end
                        end
                    end
                    if foundMeta or source.type == "unary" then
                        break
                    end
                end
            end
            if not foundMeta and (op == "==" or op == "~=") then
                pushQueue(makeNameType("boolean"), start, true)
            end
        end
    end
end

function m.pushResult(status, mode, ref, simple)
    local results = status.results
    local count = #results
    if mode == 'def' then
        if m.typeAnnTypes[ref.type] then
            results[#results+1] = ref
        elseif ref.type == 'setglobal'
        or     ref.type == 'setlocal'
        or     ref.type == 'local' then
            results[#results+1] = ref
        elseif ref.type == 'setfield'
        or     ref.type == 'tablefield' then
            results[#results+1] = ref
        elseif ref.type == 'setmethod' then
            results[#results+1] = ref
        elseif ref.type == 'setindex'
        or     ref.type == 'tableindex' then
            results[#results+1] = ref
        elseif ref.type == 'call' then
            if ref.node.special == 'rawset' then
                results[#results+1] = ref
            end
        elseif ref.type == 'function' then
            results[#results+1] = ref
        elseif ref.type == 'table' then
            results[#results+1] = ref
        elseif ref.type == 'doc.type.function'
        or     ref.type == 'doc.class.name'
        or     ref.type == 'doc.alias.name'
        or     ref.type == 'doc.field'
        or     ref.type == 'doc.type.table'
        or     ref.type == 'doc.type.array' then
            results[#results+1] = ref
        elseif ref.type == 'doc.type' then
            if #ref.enums > 0 or #ref.resumes > 0 then
                results[#results+1] = ref
            end
        elseif ref.type == 'metatable' then
            results[#results+1] = ref
        end
        if ref.parent and ref.parent.type == 'return' then
            if m.getParentFunction(ref) ~= m.getParentFunction(simple.node) then
                results[#results+1] = ref
            end
        end
        if ref.parent and m.isLiteral(ref) and ref ~= simple.node then
            if ref.parent.type == "callargs"
            or ref.parent.type == "binary"
            or ref.parent.type == "unary"
            or ref.parent.type == "ifexp"
            or ref.parent.type == "elseifexp" then
                results[#results+1] = ref
            end
        end
    elseif mode == 'ref' then
        if m.typeAnnTypes[ref.type] then
            results[#results+1] = ref
        elseif ref.type == 'setfield'
        or     ref.type == 'getfield'
        or     ref.type == 'tablefield' then
            results[#results+1] = ref
        elseif ref.type == 'setmethod'
        or     ref.type == 'getmethod' then
            results[#results+1] = ref
        elseif ref.type == 'setindex'
        or     ref.type == 'getindex'
        or     ref.type == 'tableindex' then
            results[#results+1] = ref
        elseif ref.type == 'setglobal'
        or     ref.type == 'getglobal'
        or     ref.type == 'local'
        or     ref.type == 'setlocal'
        or     ref.type == 'getlocal' then
            results[#results+1] = ref
        elseif ref.type == 'function' then
            results[#results+1] = ref
        elseif ref.type == 'table' then
            results[#results+1] = ref
        elseif ref.type == 'call' then
            if ref.node.special == 'rawset'
            or ref.node.special == 'rawget' then
                results[#results+1] = ref
            end
        elseif ref.type == 'doc.type.function'
        or     ref.type == 'doc.class.name'
        or     ref.type == 'doc.alias.name'
        or     ref.type == 'doc.field'
        or     ref.type == 'doc.type.table'
        or     ref.type == 'doc.type.array' then
            results[#results+1] = ref
        elseif ref.type == 'doc.type' then
            if #ref.enums > 0 or #ref.resumes > 0 then
                results[#results+1] = ref
            end
        elseif ref.type == 'metatable' then
            results[#results+1] = ref
        end
        if ref.parent and ref.parent.type == 'return' then
            results[#results+1] = ref
        end
        if ref.parent and m.isLiteral(ref) and ref ~= simple.node then
            if ref.parent.type == "callargs"
            or ref.parent.type == "binary"
            or ref.parent.type == "unary"
            or ref.parent.type == "ifexp"
            or ref.parent.type == "elseifexp" then
                results[#results+1] = ref
            end
        end
    elseif mode == 'field' then
        if ref.type == "type.field"
        or ref.type == "type.index"
        or ref.type == "type.library" then
            results[#results+1] = ref
        end
        if ref.type == 'getfield'
        or ref.type == 'getmethod'
        or (ref.type == 'getindex' and ref.index and ref.index.type == 'string') then
            local node = ref.node
            while node.node do
                node = node.node
            end
            local loc = simple.node
            if loc.type ~= "local"
            and loc.type ~= "getlocal"
            and loc.type ~= "setlocal" then
                loc = m.getParentType(loc, "local")
            end
            if loc and m.getSimpleName(node) == m.getSimpleName(loc) then
                results[#results+1] = ref
            end
        end
        if ref.type == 'setfield'
        or ref.type == 'tablefield' then
            results[#results+1] = ref
        elseif ref.type == 'setmethod' then
            results[#results+1] = ref
        elseif ref.type == 'setindex'
        or     ref.type == 'tableindex' then
            results[#results+1] = ref
        elseif ref.type == 'setglobal' then
        -- or     ref.type == 'getglobal' then
            results[#results+1] = ref
        elseif ref.type == 'call' then
            if ref.node.special == 'rawset'
            or ref.node.special == 'rawget' then
                results[#results+1] = ref
            end
        elseif ref.type == 'doc.field' then
            results[#results+1] = ref
        end
    elseif mode == 'deffield' then
        if ref.type == "type.field"
        or ref.type == "type.index"
        or ref.type == "type.library" then
            results[#results+1] = ref
        end
        if ref.type == 'setfield'
        or ref.type == 'tablefield' then
            results[#results+1] = ref
        elseif ref.type == 'setmethod' then
            results[#results+1] = ref
        elseif ref.type == 'setindex'
        or     ref.type == 'tableindex' then
            results[#results+1] = ref
        elseif ref.type == 'setglobal' then
            results[#results+1] = ref
        elseif ref.type == 'call' then
            if ref.node.special == 'rawset' then
                results[#results+1] = ref
            end
        elseif ref.type == 'doc.field' then
            results[#results+1] = ref
        end
    elseif mode == 'meta' then
        if ref.type == "metatable" then
            results[#results+1] = ref
        end
    end
    if #results > count then
        if status.currentSet then
            if not status.sets[status.currentSet] then
                status.sets[status.currentSet] = {}
            end
            table.insert(status.sets[status.currentSet], results[#results])
        end
    end
end

function m.checkSameSimpleName(ref, sm)
    if sm == m.ANY then
        return true
    end
    if ref.type == "type.index" then
        if ref.instanceIndex then
            return not m.eachChildOfLibrary(ref.parent, function (child)
                if m.getSimpleName(child) == sm then
                    return true
                end
            end)
        else
            for _, field in ipairs(ref.parent) do
                if field ~= ref and m.getSimpleName(field) == sm then
                    return false
                end
            end
        end
        return true
    elseif ref.parent and ref.parent.type == "type.table" and ref.type ~= "type.field" then
        return true
    end
    if m.getSimpleName(ref) == sm then
        return true
    end
    if  ref.type == 'doc.type'
    and ref.array == true then
        return true
    end
    return false
end

function m.isValidSetRef(ref)
    if m.isSet(ref) then
        return true
    end
end

function m.checkSameSimple(status, simple, ref, start, force, mode, pushQueue)
    if start > #simple then
        return
    end
    for i = start, #simple do
        local sm = simple[i]
        if not force and not m.checkSameSimpleName(ref, sm) then
            return
        end
        force = false
        local cmode = mode
        local skipSearch
        if i < #simple then
            cmode = 'ref'
        else
            if mode == 'deffield' then
                if not m.isSet(ref) then
                    skipSearch = true
                end
            end
        end
        -- 检查 doc
        local skipInfer = m.checkSameSimpleByBindDocs(status, ref, i, pushQueue, cmode)
                    or    m.checkSameSimpleByDoc(status, ref, i, pushQueue, cmode)
                    or    m.checkSameSimpleByTypeAnn(status, ref, i, pushQueue, cmode)
                    or    m.checkSameSimpleInLiteral(status, ref, i, pushQueue, cmode)
                    or    m.checkSameSimpleInMeta(status, ref, i, pushQueue, cmode)
        -- 检查自己作为 setmetatable 第一个参数的情况
        m.checkSameSimpleInArg1OfSetMetaTable(status, ref, i, pushQueue)
        -- 检查自己是字符串的分支情况
        if not skipInfer and not skipSearch then
            -- 穿透 self:func 与 mt:func
            m.searchSameFieldsCrossMethod(status, ref, i, pushQueue, cmode)
            -- 穿透赋值
            if cmode ~= "field" and cmode ~= "deffield" then
                m.searchSameFieldsInValue(status, ref, i, pushQueue, cmode)
            end
            -- 检查自己是字面量表的情况
            m.checkSameSimpleInValueOfTable(status, ref, i, pushQueue)
            -- self 的特殊处理
            m.checkSameSimpleInParamSelf(status, ref, i, pushQueue)
            -- 自己是 call 的情况
            m.checkSameSimpleInCall(status, ref, i, pushQueue, cmode)
            m.checkSameSimpleInCallbackParam(status, ref, i, pushQueue)
            m.checkSameSimpleInBinaryOrUnary(status, ref, i, pushQueue, cmode)
            m.checkSameSimpleInIfExp(status, ref, i, pushQueue, cmode)
            -- 检查形如 for k,v in pairs()/ipairs() do end 的情况
            m.checkSameSimpleAsKeyOrValueInForPairs(status, ref, i, pushQueue)
            if cmode == 'ref' then
                -- 检查形如 { a = f } 的情况
                m.checkSameSimpleAsTableField(status, ref, i, pushQueue)
                -- 检查形如 return m 的情况
                m.checkSameSimpleAsReturn(status, ref, i, pushQueue)
                -- 检查形如 a = f 的情况
                -- m.checkSameSimpleAsSetValue(status, ref, i, pushQueue)
                -- 检查自己是函数参数的情况（泛型） local x = call(V)
                m.checkSameSimpleAsCallArg(status, ref, i, pushQueue)
            end
        end
        if i == #simple then
            break
        end
        ref = m.getNextRef(ref)
        if not ref then
            return
        end
    end
    m.pushResult(status, mode, ref, simple)
    local value = m.getObjectValue(ref)
    if value then
        m.pushResult(status, mode, value, simple)
    end
end

local queuesPool = {}
local startsPool = {}
local forcesPool = {}
local poolSize = 0

local function allocQueue()
    if poolSize <= 0 then
        return {}, {}, {}
    else
        local queues = queuesPool[poolSize]
        local starts = startsPool[poolSize]
        local forces = forcesPool[poolSize]
        poolSize = poolSize - 1
        return queues, starts, forces
    end
end

local function deallocQueue(queues, starts, forces)
    poolSize = poolSize + 1
    queuesPool[poolSize] = queues
    startsPool[poolSize] = starts
    forcesPool[poolSize] = forces
end

function m.searchSameFields(status, simple, mode)
    local queues, starts, forces = allocQueue()
    local queueLen = 0
    local locks = {}
    local function appendQueue(obj, start, force, ref)
        if obj.type == "local" and m.isOpaqued(obj, ref, status) then
            return true
        end
        local lock = locks[start]
        if not lock then
            lock = {}
            locks[start] = lock
        end
        if lock[obj] then
            return false
        end
        lock[obj] = true
        if obj.original then
            if lock[obj.original] then
                return false
            end
            lock[obj.original] = true
        end
        queueLen = queueLen + 1
        queues[queueLen] = obj
        starts[queueLen] = start
        forces[queueLen] = force
        if obj.mirror then
            if not lock[obj.mirror] then
                lock[obj.mirror] = true
                queueLen = queueLen + 1
                queues[queueLen] = obj.mirror
                starts[queueLen] = start
                forces[queueLen] = force
            end
        end
        return true
    end
    local function pushQueue(obj, start, force)
        local nodeRef
        if obj.type == 'getlocal'
        or obj.type == 'setlocal' then
            nodeRef = obj
            obj = obj.node
        end
        if appendQueue(obj, start, force, nodeRef) == false then
            -- no need to process the rest if obj is already locked
            return
        end
        if obj.type == 'local' and obj.ref then
            for _, ref in ipairs(m.getVisibleRefs(obj, status)) do
                appendQueue(ref, start, force)
            end
        end
        if m.isGlobal(obj) then
            local refs = m.checkSameSimpleInGlobal(status, obj)
            if refs then
                for _, ref in ipairs(refs) do
                    appendQueue(ref, start, force)
                end
            end
        end
    end

    pushQueue(simple.node, 1)

    local max = 0
    for i = 1, 1e6 do
        if queueLen <= 0 then
            break
        end
        local obj   = queues[queueLen]
        local start = starts[queueLen]
        local force = forces[queueLen]
        queues[queueLen] = nil
        starts[queueLen] = nil
        forces[queueLen] = nil
        queueLen = queueLen - 1
        max = max + 1
        status.share.count = status.share.count + 1
        if status.share.count % 10000 == 0 then
            --if TEST then
            --    print('####', status.share.count, osClock() - status.clock)
            --end
            if status.interface and status.interface.pulse then
                status.interface.pulse()
            end
        end
        --if status.share.count >= 100000 then
        --    logWarn('Count too large!')
        --    break
        --end
        m.checkSameSimple(status, simple, obj, start, force, mode, pushQueue)
        if max >= 10000 then
            logWarn('Queue too large!')
            break
        end
    end
    --deallocQueue(queues, starts, forces)
end

function m.getCallerInSameFile(status, func)
    -- 搜索所有所在函数的调用者
    local funcRefs = m.status(status)
    m.searchRefOfValue(funcRefs, func)

    local calls = {}
    if #funcRefs.results == 0 then
        return calls
    end
    for _, res in ipairs(funcRefs.results) do
        local call = res.parent
        if call.type == 'call' then
            calls[#calls+1] = call
        end
    end
    return calls
end

function m.getCallerCrossFiles(status, main)
    if (not status.options.sameFile) and status.interface.link then
        return status.interface.link(main.uri)
    end
    return {}
end

function m.searchRefsAsFunctionReturn(status, obj, mode)
    if not status.deep then
        return
    end
    if mode == 'def' then
        return
    end
    if m.checkReturnMark(status, obj, true) then
        return
    end
    status.results[#status.results+1] = obj
    -- 搜索所在函数
    local currentFunc = m.getParentFunction(obj)
    local rtn = obj.parent
    if rtn.type ~= 'return' then
        return
    end
    -- 看看他是第几个返回值
    local index
    for i = 1, #rtn do
        if obj == rtn[i] then
            index = i
            break
        end
    end
    if not index then
        return
    end
    local calls
    if currentFunc.type == 'main' then
        calls = m.getCallerCrossFiles(status, currentFunc)
    else
        calls = m.getCallerInSameFile(status, currentFunc)
    end
    -- 搜索调用者的返回值
    if #calls == 0 then
        return
    end
    local selects = {}
    for i = 1, #calls do
        local parent = calls[i].parent
        if parent.type == 'select' and parent.index == index then
            selects[#selects+1] = parent.parent
        end
        local extParent = calls[i].extParent
        if extParent then
            for j = 1, #extParent do
                local ext = extParent[j]
                if ext.type == 'select' and ext.index == index then
                    selects[#selects+1] = ext.parent
                end
            end
        end
    end
    -- 搜索调用者的引用
    for i = 1, #selects do
        m.searchRefs(status, selects[i], 'ref')
    end
end

function m.searchRefsAsFunctionSet(status, obj, mode)
    local parent = obj.parent
    if not parent then
        return
    end
    if parent.type == 'local'
    or parent.type == 'setlocal'
    or parent.type == 'setglobal'
    or parent.type == 'setfield'
    or parent.type == 'setmethod'
    or parent.type == 'tablefield' then
        m.searchRefs(status, parent, mode)
    elseif parent.type == 'setindex'
    or     parent.type == 'tableindex' then
        if parent.index == obj then
            m.searchRefs(status, parent, mode)
        end
    end
end

function m.searchRefsAsFunction(status, obj, mode)
    if  obj.type ~= 'function'
    and obj.type ~= 'table' then
        return
    end
    m.searchRefsAsFunctionSet(status, obj, mode)
    -- 检查自己作为返回函数时的引用
    m.searchRefsAsFunctionReturn(status, obj, mode)
end

function m.cleanResults(results)
    local mark = {}
    for i = #results, 1, -1 do
        local res = results[i]
        if res.tag == 'self'
        or mark[res] then
            results[i] = results[#results]
            results[#results] = nil
        else
            mark[res] = true
        end
    end
end

function m.getRefCache(status, obj, mode)
    local isDeep = status.deep
    if mode == 'infer' then
        if not isDeep then
            return nil, nil
        end
    end
    local globalCache = status.interface.cache and status.interface.cache(status.options) or {}
    if m.isGlobal(obj) then
        local key = m.getKeyName(obj)
        if key ~= "script" then
            obj = key
        end
    end
    if not obj then
        return {}
    end
    if not globalCache[mode] then
        globalCache[mode] = {}
    end
    local sourceCache = globalCache[mode][obj]
    if sourceCache then
        return sourceCache
    end
    if not status.share.cacheLock[mode] then
        status.share.cacheLock[mode] = {}
    end
    if status.share.cacheLock[mode][obj] then
        return {}
    end
    status.share.cacheLock[mode][obj] = {}
    return nil, function (results)
        sourceCache = {}
        for i = 1, #results do
            sourceCache[i] = results[i]
        end
        globalCache[mode][obj] = sourceCache
        if not isDeep then
            return
        end
        if mode == 'ref'
        or mode == 'def' then
            for i = 1, #results do
                local res = results[i]
                if not globalCache[mode][res] then
                    globalCache[mode][res] = sourceCache
                end
            end
        end
    end
end

function m.searchRefs(status, obj, mode)
    if not obj then
        return
    end
    local cache, makeCache = m.getRefCache(status, obj, mode)
    if cache then
        for i = 1, #cache do
            status.results[#status.results+1] = cache[i]
        end
        return
    end

    -- 检查单步引用
    tracy.ZoneBeginN('searchRefs getStepRef')
    local res = m.getStepRef(status, obj, mode)
    if res then
        for i = 1, #res do
            status.results[#status.results+1] = res[i]
        end
    end
    tracy.ZoneEnd()
    -- 检查simple
    tracy.ZoneBeginN('searchRefs searchSameFields')
    if m.checkStatusDepth(status) then
        local simple = m.getSimple(obj)
        if simple then
            -- if simple[#simple] ~= m.ANY then
            --     m.searchSameFields(status, simple, mode)
            -- end
            m.searchSameFields(status, simple, mode)
        end
    end
    tracy.ZoneEnd()
    m.cleanResults(status.results)
    if makeCache then
        makeCache(status.results)
    end
end

function m.searchRefOfValue(status, obj)
    local var = obj.parent
    if var.type == 'local'
    or var.type == 'set' then
        return m.searchRefs(status, var, 'ref')
    end
end

function m.allocInfer(o)
    if type(o.type) == 'table' then
        local infers = {}
        for i = 1, #o.type do
            infers[i] = {
                type   = o.type[i],
                value  = o.value,
                source = o.source,
                level  = o.level
            }
        end
        return infers
    else
        return {
            [1] = o,
        }
    end
end

function m.mergeTypes(types)
    local hasAny = types['any']

    types['any'] = nil

    if not next(types) then
        return 'any'
    end
    -- 同时包含 number 与 integer 时，去掉 integer
    if types['number'] and types['integer'] then
        types['integer'] = nil
    end

    local results = {}
    for tp in pairs(types) do
        results[#results+1] = tp
    end
    -- 只有显性的 nil 与 any 时，取 any
    if #results == 1 then
        if results[1] == 'nil' and hasAny then
            return 'any'
        else
            return results[1]
        end
    end

    tableSort(results, function (a, b)
        local sa = TypeSort[a] or 100
        local sb = TypeSort[b] or 100
        if sa == sb then
            return a < b
        else
            return sa < sb
        end
    end)

    local enumsLimit = config.config.hover.enumsLimit
    if #results > enumsLimit then
        return tableConcat(results, ' | ', 1, enumsLimit)
            .. lang.script('HOVER_MORE_ENUMS', #results - enumsLimit)
    else
        return tableConcat(results, ' | ')
    end
end

function m.getClassExtends(class)
    if class.type == 'doc.class.name' then
        class = class.parent
    end
    if not class.extends then
        return nil
    end
    local names = {}
    for _, ext in ipairs(class.extends) do
        names[#names+1] = ext[1]
    end
    return names
end

function m.buildTypeAnn(typeUnit, mark)
    mark = mark or {}
    local text = "*unknown*"
    if not typeUnit then
        return text
    end
    if mark[typeUnit] then
        return "<CYCLE>"
    end
    if typeUnit.type ~= "type.name" then
        mark[typeUnit] = true
    end
    if typeUnit.type == "type.name"
    or typeUnit.type == "type.parameter"
    or typeUnit.type == "name" then
        local name = typeUnit[1]
        if typeUnit.generics then
            name = name .. m.buildTypeAnn(typeUnit.generics, mark)
        end
        text = name
    elseif typeUnit.type == "type.generics" then
        local types = {}
        for i = 1, #typeUnit do
            types[#types+1] = m.buildTypeAnn(typeUnit[i], mark)
        end
        text = "<" .. table.concat(types, ", ") .. ">"
    elseif typeUnit.type == "type.union" then
        local types = {}
        for i = 1, #typeUnit do
            types[#types+1] = m.buildTypeAnn(typeUnit[i], mark)
            if typeUnit[i].type == "type.function" then
                types[#types] = "(" .. types[#types] .. ")"
            end
        end
        text = table.concat(types, " | ")
    elseif typeUnit.type == "type.inter" then
        local types = {}
        for i = 1, #typeUnit do
            types[#types+1] = m.buildTypeAnn(typeUnit[i], mark)
            if typeUnit[i].type == "type.function" then
                types[#types] = "(" .. types[#types] .. ")"
            end
        end
        text = table.concat(types, " & ")
    elseif typeUnit.type == "type.function" then
        text = m.buildTypeAnn(typeUnit.args, mark) .. " -> " .. m.buildTypeAnn(typeUnit.returns, mark)
    elseif typeUnit.type == "type.list" then
        local types = {}
        for i = 1, #typeUnit do
            types[#types+1] = m.buildTypeAnn(typeUnit[i], mark)
            if typeUnit[i].paramName then
                types[#types] = typeUnit[i].paramName[1] .. ": " .. types[#types]
            end
        end
        text = "(" .. table.concat(types, ", ") .. ")"
    elseif typeUnit.type == "type.table" then
        local fields = {}
        for i = 1, #typeUnit do
            fields[#fields+1] = m.buildTypeAnn(typeUnit[i], mark)
        end
        text = "{" .. table.concat(fields, ", ") .. "}"
    elseif typeUnit.type == "type.field" then
        text = typeUnit.key[1] .. ": " .. m.buildTypeAnn(typeUnit.value, mark)
    elseif typeUnit.type == "type.library" then
        text = typeUnit.name .. ": " .. m.buildTypeAnn(typeUnit.value, mark)
    elseif typeUnit.type == "type.index" then
        text = "[" .. m.buildTypeAnn(typeUnit.key, mark) .. "]: " .. m.buildTypeAnn(typeUnit.value, mark)
    elseif typeUnit.type == "type.module" then
        text = typeUnit[1][1] .. "." .. m.buildTypeAnn(typeUnit[2], mark)
    elseif typeUnit.type == "type.variadic" then
        text = "..." .. m.buildTypeAnn(typeUnit.value, mark)
    elseif typeUnit.type == "type.typeof" then
        text = "typeof(" .. m.buildExp(typeUnit.value) .. ")"
    elseif typeUnit.type == "type.singleton.string" then
        text = "\"" .. typeUnit[1] .. "\""
    elseif typeUnit.type == "type.singleton.boolean" then
        text = tostring(typeUnit[1])
    elseif typeUnit.type == "type.genericpack" then
        text = typeUnit[1] .. "..."
    elseif typeUnit.type == "type.meta" then
        text = "{" .. m.buildTypeAnn(typeUnit[1], mark) .. ", @metatable " .. m.buildTypeAnn(typeUnit[2], mark) .. "}"
    elseif typeUnit.type == "paren" then
        text = "(" .. m.buildTypeAnn(typeUnit.exp, mark) .. ")"
    end
    if typeUnit.optional then
        text = text .. "?"
    end
    return text
end

function m.buildExp(expUnit, mark)
    mark = mark or {}
    local text = "*unknown*"
    if not expUnit then
        return text
    end
    if mark[expUnit] then
        return "<CYCLE>"
    end
    mark[expUnit] = true
    if expUnit.type == "paren" then
        text = "(" .. m.buildExp(expUnit.exp, mark) .. ")"
    elseif expUnit.type == "getlocal" or expUnit.type == "getglobal" then
        text = expUnit[1]
        return text
    elseif expUnit.type == "getfield" then
        text = "." .. expUnit.field[1]
    elseif expUnit.type == "getmethod" then
        text = ":" .. expUnit.method[1]
    elseif expUnit.type == "getindex" then
        text = "[" .. m.buildExp(expUnit.index) .. "]"
    elseif expUnit.type == "call" then
        text = "()"
    elseif expUnit.type == "binary" then
        text = m.buildExp(expUnit[1]) .. " " .. expUnit.op.type .. " " .. m.buildExp(expUnit[2])
    elseif expUnit.type == "unary" then
        text = expUnit.op.type .. m.buildExp(expUnit[1])
    elseif expUnit.type == "string" then
        text = "\"" .. expUnit[1] .. "\""
    elseif expUnit.type == "number" then
        text = tostring(expUnit[1])
    elseif expUnit.type == "boolean" then
        text = tostring(expUnit[1])
    elseif expUnit.type == "table" then
        text = "*table*"
    elseif expUnit.type == "function" then
        text = "*function*"
    end
    if expUnit.node then
        text = m.buildExp(expUnit.node) .. text
    end
    return text
end

function m.viewInferType(infers)
    if not infers then
        return 'any'
    end
    local types = {}
    local hasDoc
    local hasDocTable
    for i = 1, #infers do
        local infer = infers[i]
        local src = infer.source
        if src.type == 'doc.class'
        or src.type == 'doc.class.name'
        or src.type == 'doc.type.name'
        or src.type == 'doc.type.array'
        or src.type == 'doc.type.table' then
            if infer.type ~= 'any' then
                hasDoc = true
            end
            if src.type == 'doc.type.array'
            or src.type == 'doc.type.table' then
                hasDocTable = true
            end
        end
    end
    if hasDoc then
        for i = 1, #infers do
            local infer = infers[i]
            local src = infer.source
            if src.type == 'doc.class'
            or src.type == 'doc.class.name'
            or src.type == 'doc.type.name'
            or src.type == 'doc.type.array'
            or src.type == 'doc.type.table'
            or src.type == 'doc.type.enum'
            or src.type == 'doc.resume' then
                local tp = infer.type or 'any'
                if hasDocTable and tp == 'table' then
                    goto CONTINUE
                end
                if types[tp] == nil then
                    types[tp] = true
                end
            end
            if src.type == 'doc.class'
            or src.type == 'doc.class.name' then
                local extends = m.getClassExtends(src)
                if extends then
                    for _, tp in ipairs(extends) do
                        types[tp] = false
                    end
                end
            end
            ::CONTINUE::
        end
        for k, v in pairs(types) do
            if not v then
                types[k] = nil
            end
        end
    else
        for i = 1, #infers do
            local infer = infers[i]
            if infer.source.typeGeneric then
                goto CONTINUE
            end
            local tp = infer.type or 'any'
            types[tp] = true
            ::CONTINUE::
        end
    end
    return m.mergeTypes(types)
end

--- 获取特定类型的字面量值
function m.getInferLiteral(status, source, type)
    local newStatus = m.status(status)
    m.searchInfer(newStatus, source)
    for _, infer in ipairs(newStatus.results) do
        if infer.value ~= nil then
            if type == nil or infer.type == type then
                return infer.value
            end
        end
    end
    return nil
end

--- 是否包含某种类型
function m.hasType(status, source, type)
    m.searchInfer(status, source)
    for _, infer in ipairs(status.results) do
        if infer.type == type then
            return true
        end
    end
    return false
end

function m.getType(status, source)
    if not source then
        return
    end
    source = m.getObjectValue(source) or source
    if not status.share.getTypeCache then
        status.share.getTypeCache = {}
    end
    if status.share.getTypeCache[source] then
        return status.share.getTypeCache[source]
    end
    if m.isLiteral(source) then
        local tp = makeNameType(source.type)
        if source.type == "string" or source.type == "boolean" then
            tp.inferValue = source[1]
        end
        return tp
    elseif m.isTypeAnn(source) then
        local tp = m.getFullType(status, source)
        status.share.getTypeCache[source] = tp
        return tp
    end
    local newStatus = m.status(status)
    newStatus.searchFrom = source
    m.searchRefs(newStatus, source, "def")
    local union = {
        type = "type.union"
    }
    for _, def in ipairs(newStatus.results) do
        def = m.getObjectValue(def) or def
        if m.isLiteral(def) then
            local tp = makeNameType(def.type)
            if def.type == "string" or def.type == "boolean" then
                tp.inferValue = def[1]
            end
            union[#union+1] = tp
        elseif m.typeAnnTypes[def.type] then
            local tp = m.getFullType(status, def)
            union[#union+1] = tp
        end
    end
    if #union == 0 then
        union = nil
    elseif #union == 1 then
        union = union[1]
    end
    status.share.getTypeCache[source] = union
    return union
end

function m.getTypeCount(list)
    local number = 0
    for _, arg in ipairs(list) do
        if arg.type == "type.variadic" then
            number = math.huge
        else
            number = number + 1
        end
    end
    return number
end

function m.isSameValue(status, a, b)
    local statusA = m.status(status)
    m.searchInfer(statusA, a)
    local statusB = m.status(status)
    m.searchInfer(statusB, b)
    local infers = {}
    for _, infer in ipairs(statusA.results) do
        local literal = infer.value
        if literal then
            infers[literal] = false
        end
    end
    for _, infer in ipairs(statusB.results) do
        local literal = infer.value
        if literal then
            if infers[literal] == nil then
                return false
            end
            infers[literal] = true
        end
    end
    for k, v in pairs(infers) do
        if v == false then
            return false
        end
    end
    return true
end

function m.inferCheckTypeAnn(status, source)
    if status.options.skipType then
        return false
    end
    local typeAnn = source.typeAnn or (source.parent and source.parent.typeAnn)
    if typeAnn then
        typeAnn = typeAnn.value
    elseif source.type == "type.assert" then
        typeAnn = source[2]
    elseif m.isTypeAnn(source) then
        typeAnn = source
    else
        return false
    end
    if typeAnn.type == "type.field"
    or typeAnn.type == "type.index" then
        typeAnn = typeAnn.value
    end
    if typeAnn.type == "type.typeof" then
        return false
    end
    if status.options.fullType then
        typeAnn = m.getFullType(status, typeAnn)
    end
    status.results = m.allocInfer {
        type = m.buildTypeAnn(typeAnn),
        source = typeAnn,
        level  = 100,
    }
    return true
end

function m.inferCheckLiteralTableWithDocVararg(status, source)
    if #source ~= 1 then
        return
    end
    local vararg = source[1]
    if vararg.type ~= 'varargs' then
        return
    end
    local results = m.getVarargDocType(status, source)
    status.results[#status.results+1] = {
        type   = m.viewInferType(results) .. '[]',
        source = source,
        level  = 100,
    }
    return true
end

function m.inferCheckLiteral(status, source)
    if source.type == 'string' then
        status.results = m.allocInfer {
            type   = 'string',
            value  = source[1],
            source = source,
            level  = 100,
        }
        return true
    elseif source.type == 'nil' then
        local parent = source.parent
        if  parent
        and parent.type == "local"
        or  parent.type == "tablefield"
        or  parent.type == "tableindex" then
            status.results = m.allocInfer {
                type   = 'any',
                source = source,
                level  = 100,
            }
        else
            status.results = m.allocInfer {
                type   = 'nil',
                value  = NIL,
                source = source,
                level  = 100,
            }
        end
        return true
    elseif source.type == 'boolean' then
        status.results = m.allocInfer {
            type   = 'boolean',
            value  = source[1],
            source = source,
            level  = 100,
        }
        return true
    elseif source.type == 'number' or source.type == 'integer' then
        status.results = m.allocInfer {
            type   = 'number',
            value  = source[1],
            source = source,
            level  = 100,
        }
        return true
    elseif source.type == 'table' then
        -- if m.inferCheckLiteralTableWithDocVararg(status, source) then
        --     return true
        -- end
        status.results = m.allocInfer {
            type   = 'table',
            source = source,
            level  = 100,
        }
        return true
    elseif source.type == 'function' then
        status.results = m.allocInfer {
            type   = 'function',
            source = source,
            level  = 100,
        }
        return true
    elseif source.type == '...' then
        status.results = m.allocInfer {
            type   = '...',
            source = source,
            level  = 100,
        }
        return true
    end
end

local function getDocAliasExtends(status, typeUnit)
    if not status.interface.docType then
        return nil
    end
    if typeUnit.type ~= 'doc.type.name' then
        return nil
    end
    for _, doc in ipairs(status.interface.docType(typeUnit[1])) do
        if doc.type == 'doc.alias.name' then
            return doc.parent.extends
        end
    end
    return nil
end

function m.getDocTypeUnitName(status, unit)
    local typeName
    if unit.type == 'doc.type.name' then
        typeName = unit[1]
    elseif unit.type == 'doc.type.function' then
        typeName = 'function'
    elseif unit.type == 'doc.type.array' then
        typeName = m.getDocTypeUnitName(status, unit.node) .. '[]'
    elseif unit.type == 'doc.type.table' then
        typeName = ('%s<%s, %s>'):format(
            m.getDocTypeUnitName(status, unit.node),
            m.viewInferType(m.getDocTypeNames(status, unit.key)),
            m.viewInferType(m.getDocTypeNames(status, unit.value))
        )
    end
    if unit.typeGeneric then
        typeName = ('<%s>'):format(typeName)
    end
    return typeName
end

function m.getDocTypeNames(status, doc)
    local results = {}
    if not doc then
        return results
    end
    for _, unit in ipairs(doc.types) do
        local alias = getDocAliasExtends(status, unit)
        if alias then
            local aliasResults = m.getDocTypeNames(status, alias)
            for _, res in ipairs(aliasResults) do
                results[#results+1] = res
            end
        else
            local typeName = m.getDocTypeUnitName(status, unit)
            results[#results+1] = {
                type   = typeName,
                source = unit,
                level  = 100,
            }
        end
    end
    for _, enum in ipairs(doc.enums) do
        results[#results+1] = {
            type   = enum[1],
            source = enum,
            level  = 100,
        }
    end
    for _, resume in ipairs(doc.resumes) do
        if not resume.additional then
            results[#results+1] = {
                type   = resume[1],
                source = resume,
                level  = 100,
            }
        end
    end
    return results
end

function m.inferCheckDoc(status, source)
    if status.options.skipDoc then
        return false
    end
    if source.type == 'doc.class.name' then
        status.results[#status.results+1] = {
            type   = source[1],
            source = source,
            level  = 100,
        }
        return true
    end
    if source.type == 'doc.class' then
        status.results[#status.results+1] = {
            type   = source.class[1],
            source = source,
            level  = 100,
        }
        return true
    end
    if source.type == 'doc.type' then
        local results = m.getDocTypeNames(status, source)
        for _, res in ipairs(results) do
            status.results[#status.results+1] = res
        end
        return true
    end
    if source.type == 'doc.type.function'
    or source.type == 'doc.type.table'
    or source.type == 'doc.type.array' then
        local typeName = m.getDocTypeUnitName(status, source)
        status.results[#status.results+1] = {
            type   = typeName,
            source = source,
            level  = 100,
        }
        return true
    end
    if source.type == 'doc.field' then
        local results = m.getDocTypeNames(status, source.extends)
        for _, res in ipairs(results) do
            status.results[#status.results+1] = res
        end
        return true
    end
    if source.type == 'doc.alias.name' then
        local results = m.getDocTypeNames(status, m.getDocState(source).extends)
        for _, res in ipairs(results) do
            status.results[#status.results+1] = res
        end
        return true
    end
end

function m.getVarargDocType(status, source)
    local func = m.getParentFunction(source)
    if not func then
        return
    end
    if not func.args then
        return
    end
    for _, arg in ipairs(func.args) do
        if arg.type == '...' then
            if arg.bindDocs then
                for _, doc in ipairs(arg.bindDocs) do
                    if doc.type == 'doc.vararg' then
                        return m.getDocTypeNames(status, doc.vararg)
                    end
                end
            end
        end
    end
end

function m.inferCheckUpDocOfVararg(status, source)
    if not source.vararg then
        return
    end
    local results = m.getVarargDocType(status, source)
    if not results then
        return
    end
    for _, res in ipairs(results) do
        status.results[#status.results+1] = res
    end
    return true
end

function m.inferCheckUpDoc(status, source)
    if status.options.skipDoc then
        return false
    end
    if m.inferCheckUpDocOfVararg(status, source) then
        return true
    end
    local parent = source.parent
    if parent then
        if parent.type == 'local'
        or parent.type == 'setlocal'
        or parent.type == 'setglobal' then
            source = parent
        end
        if parent.type == 'setfield'
        or parent.type == 'tablefield' then
            if parent.field == source
            or parent.value == source then
                source = parent
            end
        end
        if parent.type == 'setmethod' then
            if parent.method == source
            or parent.value == source then
                source = parent
            end
        end
        if parent.type == 'setindex'
        or parent.type == 'tableindex' then
            if parent.index == source
            or parent.value == source then
                source = parent
            end
        end
    end
    local binds = source.bindDocs
    if not binds then
        return
    end
    status.results = {}
    for i = #binds, 1, -1 do
        local doc = binds[i]
        if doc.type == 'doc.class' then
            status.results[#status.results+1] = {
                type   = doc.class[1],
                source = doc,
                level  = 100,
            }
            -- ---@class Class
            -- local x = { field = 1 }
            -- 这种情况下，将字面量表接受为Class的定义
            if source.value and source.value.type == 'table' then
                status.results[#status.results+1] = {
                    type   = source.value.type,
                    source = source.value,
                    level  = 100,
                }
            end
            return true
        elseif doc.type == 'doc.type' then
            local results = m.getDocTypeNames(status, doc)
            for _, res in ipairs(results) do
                status.results[#status.results+1] = res
            end
            return true
        elseif doc.type == 'doc.param' then
            -- function (x) 的情况
            if  source.type == 'local'
            and m.getKeyName(source) == doc.param[1] then
                if source.parent.type == 'funcargs'
                or source.parent.type == 'in'
                or source.parent.type == 'loop' then
                    local results = m.getDocTypeNames(status, doc.extends)
                    for _, res in ipairs(results) do
                        status.results[#status.results+1] = res
                    end
                    return true
                end
            end
        elseif doc.type == "doc.module" then
            if status.interface.module then
                local rets = status.interface.module(doc)
                for _, ret in ipairs(rets) do
                    m.searchInfer(status, ret)
                end
            end
            return true
        end
    end
end

function m.inferByDef(status, obj, main)
    if not status.share.inferedDef then
        status.share.inferedDef = {}
    end
    if status.share.inferedDef[obj] then
        return
    end
    status.share.inferedDef[obj] = true
    local mark = {}
    local newStatus = m.status(status)
    tracy.ZoneBeginN('inferByDef searchRefs')
    m.searchRefs(newStatus, obj, 'def')
    if main and status.main == main and not status.options.searchAll then
        newStatus.main, newStatus.searchFrom = status.main, status.searchFrom
        m.selectClosestsRefs(newStatus, "def")
    end
    tracy.ZoneEnd()
    for _, src in ipairs(newStatus.results) do
        local inferStatus = m.status(newStatus)
        if src.type == "metatable" then
            m.searchInfer(inferStatus, src.value, true)
        else
            m.searchInfer(inferStatus, src)
        end
        if #inferStatus.results == 0 then
            -- status.results[#status.results+1] = {
            --     type   = 'any',
            --     source = src,
            --     level  = 0,
            -- }
        else
            for _, infer in ipairs(inferStatus.results) do
                if not mark[infer.source] then
                    mark[infer.source] = true
                    status.results[#status.results+1] = infer
                    if src.type == "metatable" then
                        infer.meta = src
                    end
                end
            end
        end
    end
end

local function inferBySetOfLocal(status, source)
    if status.share[source] then
        return
    end
    status.share[source] = true
    local newStatus = m.status(status)
    if source.value then
        m.searchInfer(newStatus, source.value)
    end
    if source.ref then
        for _, ref in ipairs(source.ref) do
            if ref.type == 'setlocal' then
                break
            end
            m.searchInfer(newStatus, ref)
        end
        for _, infer in ipairs(newStatus.results) do
            status.results[#status.results+1] = infer
        end
    end
end

function m.inferByLocalRef(status, source)
    if #status.results ~= 0 then
        return
    end
    if source.type == 'local' then
        inferBySetOfLocal(status, source)
    elseif source.type == 'setlocal'
    or     source.type == 'getlocal' then
        inferBySetOfLocal(status, source.node)
    end
end

function m.cleanInfers(infers, obj)
    -- kick lower level infers
    local level = 0
    if obj.type ~= 'select' then
        for i = 1, #infers do
            local infer = infers[i]
            if infer.level > level then
                level = infer.level
            end
        end
    end
    -- merge infers
    local mark = {}
    local parenValue = {}
    for i = #infers, 1, -1 do
        local infer = infers[i]
        if infer.level < level then
            infers[i] = infers[#infers]
            infers[#infers] = nil
            goto CONTINUE
        end
        local key = ('%p'):format(infer.meta or infer.type)
        if mark[key] then
            infers[i] = infers[#infers]
            infers[#infers] = nil
        else
            mark[key] = true
            if infer.source.type == "paren" then
                local value = m.getObjectValue(infer.source)
                if m.typeAnnTypes[value.type] then
                    parenValue[value] = true
                end
            end
        end
        ::CONTINUE::
    end
    -- kick doc.generic
    if #infers > 1 then
        for i = #infers, 1, -1 do
            local infer = infers[i]
            if infer.source.typeGeneric or parenValue[infer.source] then
                infers[i] = infers[#infers]
                infers[#infers] = nil
            end
        end
    end
end

function m.searchInfer(status, obj, deep)
    local main = obj
    while true do
        local value = m.getObjectValue(obj)
        if not value or value == obj then
            break
        end
        obj = value
    end
    while obj.type == 'paren' do
        obj = obj.exp
        if not obj then
            return
        end
    end
    if not obj then
        return
    end
    local cache, makeCache = m.getRefCache(status, obj, 'infer')
    if cache then
        for i = 1, #cache do
            status.results[#status.results+1] = cache[i]
        end
        return
    end

    if DEVELOP then
        status.share.clock = status.share.clock or osClock()
    end

    if not status.share.lockInfer then
        status.share.lockInfer = {}
    end
    if status.share.lockInfer[obj] then
        return
    end
    status.share.lockInfer[obj] = true
    local checked = m.inferCheckDoc(status, obj)
                 or m.inferCheckUpDoc(status, obj)
                 or m.inferCheckTypeAnn(status, obj)
                 or m.inferCheckLiteral(status, obj)
    if checked then
        m.cleanInfers(status.results, obj)
        if makeCache then
            makeCache(status.results)
        end
        return
    end

    -- m.inferByLocalRef(status, obj)
    if status.deep or deep then
        tracy.ZoneBeginN('inferByDef')
        m.inferByDef(status, obj, main)
        tracy.ZoneEnd()
    end

    m.cleanInfers(status.results, obj)
    if makeCache then
        makeCache(status.results)
    end
end

--- 请求对象的引用，包括 `a.b.c` 形式
--- 与 `return function` 形式。
--- 不穿透 `setmetatable` ，考虑由
--- 业务层进行反向 def 搜索。
function m.requestReference(obj, interface, deep, options)
    local status = m.status(nil, nil, interface, deep, options)
    -- 根据 field 搜索引用
    m.searchRefs(status, obj, 'ref')

    m.searchRefsAsFunction(status, obj, 'ref')

    if m.debugMode then
        --print('count:', status.share.count)
    end

    return status.results, status.share.count
end

--- 请求对象的定义，包括 `a.b.c` 形式
--- 与 `return function` 形式。
--- 穿透 `setmetatable` 。
function m.requestDefinition(obj, interface, deep, options)
    local status = m.status(nil, nil, interface, deep, options)

    if options and options.onlyDef then
        status.main = obj
    end
    -- 根据 field 搜索定义
    m.searchRefs(status, obj, 'def')

    return status.results, status.share.count
end

---@param filterKey nil|string|table
function m.requestFields(obj, interface, deep, filterKey, options)
    local status = m.status(nil, obj, interface, deep, options)

    if options and options.onlyDef then
        m.searchFields(status, obj, filterKey, "deffield")
    else
        m.searchFields(status, obj, filterKey, "field")
    end

    return status.results, status.share.count
end

--- 请求对象的类型推测
function m.requestInfer(obj, interface, deep, options)
    local status = m.status(nil, obj, interface, deep, options)

    m.searchInfer(status, obj)

    return status.results, status.share.count
end

function m.requestMeta(obj, interface, deep, options)
    local status = m.status(nil, obj, interface, deep, options)

    m.searchMeta(status, obj)

    return status.results, status.share.count
end

function m.debugView(obj)
    return require 'files'.position(m.getUri(obj), obj.start), m.getUri(obj)
end

return m
