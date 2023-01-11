local defaultlibs = require 'library.defaultlibs'
local guide       = require 'core.guide'
local ipairs      = ipairs
local os          = os
local output      = output
local pairs       = pairs
local tableInsert = table.insert
local tableUnpack = table.unpack
local type        = type
local select      = select

local specials = {
    ['rawset']       = true,
    ['rawget']       = true,
    ['setmetatable'] = true,
    ['require']      = true,
    ['pcall']        = true,
    ['xpcall']       = true,
    ['pairs']        = true,
    ['ipairs']       = true,
    ['next']         = true,
    ['type']         = true,
    ['typeof']       = true,
    ['assert']       = true,
    ['table.freeze'] = true,
    ['table.clone']  = true,
}

_ENV = nil

local LocalLimit = 200
local PushError, Compile, CompileBlock, Block, ENVMode, Compiled, LocalCount, Root, Uri, Text

local function addRef(node, obj)
    if not node.ref then
        node.ref = {}
    end
    node.ref[#node.ref+1] = obj
    obj.node = node
end

local function addSpecial(name, obj)
    if not Root.specials then
        Root.specials = {}
    end
    if not Root.specials[name] then
        Root.specials[name] = {}
    end
    Root.specials[name][#Root.specials[name]+1] = obj
    obj.special = name
end

local function replaceTable(tbl1, tbl2)
    for k in pairs(tbl1) do
        tbl1[k] = nil
    end
    for k, v in pairs(tbl2) do
        tbl1[k] = v
    end
end

local function convertStrOrExp(obj, quote)
    if type(obj) == "string" then
        return {
            type = "string",
            start = 0,
            finish = 0,
            [1] = obj,
            [2] = quote
        }
    end
    return obj
end

local vmMap = {
    ['getname'] = function (obj)
        local loc = guide.getLocal(obj, obj[1], obj.start)
        if loc then
            obj.type = 'getlocal'
            obj.loc  = loc
            addRef(loc, obj)
            if loc.special then
                addSpecial(loc.special, obj)
            end
        else
            obj.type = 'getglobal'
            local node = guide.getLocal(obj, ENVMode, obj.start)
            if node then
                addRef(node, obj)
            end
            local name = obj[1]
            if specials[name] then
                addSpecial(name, obj)
            end
        end
        return obj
    end,
    ['getfield'] = function (obj)
        Compile(obj.node, obj)
        if obj.node.type == "getglobal" and obj.field  then
            local name = obj.node[1] .. "." .. obj.field[1]
            if specials[name] then
                addSpecial(name, obj)
            end
        end
    end,
    ['call'] = function (obj)
        Compile(obj.node, obj)
        if obj.node and obj.node.type == 'getmethod' then
            if not obj.args then
                obj.args = {
                    type   = 'callargs',
                    start  = obj.start,
                    finish = obj.finish,
                    parent = obj,
                }
            end
            local newNode = {}
            for k, v in pairs(obj.node.node) do
                newNode[k] = v
            end
            newNode.mirror = obj.node.node
            newNode.dummy  = true
            newNode.parent = obj.args
            obj.node.node.mirror = newNode
            tableInsert(obj.args, 1, newNode)
            Compiled[newNode] = true
        end
        Compile(obj.args, obj)
        if obj.node and obj.node.special == "require" then
            if obj.args and #obj.args == 1 then
                if not Root.requires then
                    Root.requires = {}
                end
                Root.requires[#Root.requires+1] = obj
            end
        elseif obj.node and (obj.node.special == "pcall" or obj.node.special == "xpcall") then
            if obj.args and obj.args[1] then
                obj.pcallArgs = {
                    select(obj.node.special == "pcall" and 2 or 3, tableUnpack(obj.args)),
                    type = "callargs",
                    start = obj.args.start,
                    finish = obj.args.finish
                }
                Compile(obj.pcallArgs, obj)
            end
        end
    end,
    ['callargs'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['binary'] = function (obj)
        Compile(obj[1], obj)
        Compile(obj[2], obj)
    end,
    ['unary'] = function (obj)
        Compile(obj[1], obj)
    end,
    ['varargs'] = function (obj)
        local func = guide.getParentFunction(obj)
        if func then
            local index, vararg = guide.getFunctionVarArgs(func)
            if not index then
                PushError {
                    type   = 'UNEXPECT_DOTS',
                    start  = obj.start,
                    finish = obj.finish,
                }
            end
            if vararg then
                if not vararg.ref then
                    vararg.ref = {}
                end
                vararg.ref[#vararg.ref+1] = obj
                if vararg.typeAnn then
                    obj.typeAnn = {
                        type = "type.variadic",
                        parent = obj,
                        value = vararg.typeAnn.value,
                        start = obj.start,
                        finish = obj.finish
                    }
                end
            end
        end
    end,
    ["interstring"] = function(obj)
        local str = obj[1]
        local quote = obj[2]
        local new = {
            type = "binary",
            start = obj.start,
            finish = obj.finish,
            op = {
                type = "..",
                start = 0,
                finish = 0,
            },
            parent = obj.parent,
            [1] = convertStrOrExp(str[1], quote)
        }
        local last = new
        for i = 2, #str do
            if i == #str then
                last[2] = convertStrOrExp(str[i], quote)
            else
                last[2] = {
                    type = "binary",
                    op = {
                        type = "..",
                        start = 0,
                        finish = 0,
                    },
                    start = obj.start,
                    finish = obj.finish,
                    [1] = convertStrOrExp(str[i], quote)
                }
                last = last[2]
            end
        end
        if not new[2] then
            replaceTable(new, new[1])
        end
        replaceTable(obj, new)
        Compiled[obj] = nil
        Compile(obj, obj.parent)
    end,
    ['paren'] = function (obj)
        Compile(obj.exp, obj)
    end,
    ['getindex'] = function (obj)
        Compile(obj.node, obj)
        Compile(obj.index, obj)
    end,
    ['setindex'] = function (obj)
        Compile(obj.node, obj)
        Compile(obj.index, obj)
        Compile(obj.value, obj)
    end,
    ['getmethod'] = function (obj)
        Compile(obj.node, obj)
        Compile(obj.method, obj)
    end,
    ['setmethod'] = function (obj)
        Compile(obj.node, obj)
        Compile(obj.method, obj)
        local value = obj.value
        local localself = {
            type   = 'local',
            start  = 0,
            finish = 0,
            method = obj,
            effect = obj.finish,
            tag    = 'self',
            dummy  = true,
            [1]    = 'self',
        }
        if not value.args then
            value.args = {
                type   = 'funcargs',
                start  = obj.start,
                finish = obj.finish,
            }
        end
        tableInsert(value.args, 1, localself)
        Compile(value, obj)
    end,
    ['function'] = function (obj)
        local lastBlock = Block
        local LastLocalCount = LocalCount
        Block = obj
        LocalCount = 0
        Compile(obj.args, obj)
        Compile(obj.generics, obj)
        Compile(obj.returnTypeAnn, obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
        Block = lastBlock
        LocalCount = LastLocalCount
    end,
    ['funcargs'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['table'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['tablefield'] = function (obj)
        Compile(obj.value, obj)
    end,
    ['tableindex'] = function (obj)
        Compile(obj.index, obj)
        Compile(obj.value, obj)
    end,
    ['index'] = function (obj)
        Compile(obj.index, obj)
    end,
    ['select'] = function (obj)
        local vararg = obj.vararg
        if vararg.parent then
            if not vararg.extParent then
                vararg.extParent = {}
            end
            vararg.extParent[#vararg.extParent+1] = obj
        else
            Compile(vararg, obj)
        end
    end,
    ['setname'] = function (obj)
        Compile(obj.value, obj)
        local loc = guide.getLocal(obj, obj[1], obj.start)
        if loc then
            obj.type = 'setlocal'
            obj.loc  = loc
            addRef(loc, obj)
        else
            obj.type = 'setglobal'
            local node = guide.getLocal(obj, ENVMode, obj.start)
            if node then
                addRef(node, obj)
            end
            local name = obj[1]
            if specials[name] then
                addSpecial(name, obj)
            end
        end
    end,
    ['local'] = function (obj)
        if Block then
            if not Block.locals then
                Block.locals = {}
            end
            Block.locals[#Block.locals+1] = obj
            LocalCount = LocalCount + 1
            if LocalCount > LocalLimit then
                PushError {
                    type   = 'LOCAL_LIMIT',
                    start  = obj.start,
                    finish = obj.finish,
                }
            end
        end
        if obj.localfunction then
            obj.localfunction = nil
        end
        Compile(obj.value, obj)
        if obj.value and obj.value.special then
            addSpecial(obj.value.special, obj)
        end
        Compile(obj.typeAnn, obj)
    end,
    ['...'] = function (obj)
        Compile(obj.typeAnn, obj)
    end,
    ["ifexp"] = function (obj)
        Compile(obj.filter, obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ["elseifexp"] = function (obj)
        Compile(obj.filter, obj)
        Compile(obj[1], obj)
    end,
    ['type.alias'] = function (obj)
        if Block then
            if not Block.types then
                Block.types = {}
            end
            Block.types[#Block.types+1] = obj
        end
        if obj.export and Root and Root ~= Block then
            if not Root.types then
                Root.types = {}
            end
            Root.types[#Root.types+1] = obj
        end
        Compile(obj.name, obj)
        Compile(obj.value, obj)
        Compile(obj.generics, obj)
    end,
    ['type.ann'] = function (obj)
        Compile(obj.value, obj)
    end,
    ['type.assert'] = function (obj)
        Compile(obj[1], obj)
        Compile(obj[2], obj)
    end,
    ['type.name'] = function (obj)
        if obj.parent.type ~= "type.module" then
            local parent = obj
            for _ = 1, 1000 do
                parent = parent.parent
                if not parent then
                    break
                end
                if parent.type == "type.function" or parent.type == "function" or parent.type == "type.alias" then
                    if parent.generics then
                        for _, generic in ipairs(parent.generics) do
                            if generic[1] == obj[1] then
                                generic.replace[#generic.replace+1] = obj
                                obj.typeAliasGeneric = generic
                                goto CONTINUE
                            end
                        end
                    end
                end
            end
            obj.typeAlias = guide.getTypeAliasInAst(obj, obj[1])
            if obj.typeAlias then
                obj.typeAlias.ref = obj.typeAlias.ref or {}
                obj.typeAlias.ref[#obj.typeAlias.ref+1] = obj
            end
        end
        ::CONTINUE::
        Compile(obj.generics, obj)
    end,
    ['type.table'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['type.list'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['type.union'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['type.inter'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['type.generics'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['type.parameter'] = function (obj)
        Compile(obj.default, obj)
        if obj.default and (guide.getParentType(obj, "type.function") or guide.getParentType(obj, "function")) then
            PushError {
                type   = 'UNEXPECT_TYPE',
                start  = obj.default.start,
                finish = obj.default.finish,
            }
        end
    end,
    ['type.genericpack'] = function (obj)
        Compile(obj.default, obj)
        if obj.default and (guide.getParentType(obj, "type.function") or guide.getParentType(obj, "function")) then
            PushError {
                type   = 'UNEXPECT_TYPE',
                start  = obj.default.start,
                finish = obj.default.finish,
            }
        end
    end,
    ['type.field'] = function (obj)
        Compile(obj.key, obj)
        Compile(obj.value, obj)
        obj.value.special = Text:sub(1, obj.key.start - 1):match("%-%-%-@special%s+([%w_%.]+)%s+$")
    end,
    ['type.index'] = function (obj)
        Compile(obj.key, obj)
        Compile(obj.value, obj)
    end,
    ['type.function'] = function (obj)
        Compile(obj.args, obj)
        Compile(obj.returns, obj)
        Compile(obj.generics, obj)
    end,
    ['type.module'] = function (obj)
        Compile(obj[1], obj)
        if defaultlibs.namespace[obj[1][1]] then
            obj.type = "type.name"
            obj.optional = obj[2].optional
            obj.generics = obj[2].generics
            obj.nameStart = obj[2].start
            obj[1] = obj[1][1] .. "." .. obj[2][1]
            obj[2] = nil
            Compiled[obj] = nil
            Compile(obj, obj.parent)
        else
            Compile(obj[2], obj)
        end
    end,
    ['type.variadic'] = function (obj)
        Compile(obj.value, obj)
    end,
    ['type.typeof'] = function (obj)
        Compile(obj.value, obj)
    end,
    ['setfield'] = function (obj)
        Compile(obj.node, obj)
        Compile(obj.value, obj)
    end,
    ['do'] = function (obj)
        local lastBlock = Block
        Block = obj
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['return'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
        if Block and Block[#Block] ~= obj then
            PushError {
                type   = 'ACTION_AFTER_RETURN',
                start  = obj.start,
                finish = obj.finish,
            }
        end
        local func = guide.getParentFunction(obj)
        if func then
            if not func.returns then
                func.returns = {}
            end
            func.returns[#func.returns+1] = obj
        end
    end,
    ['if'] = function (obj)
        for i = 1, #obj do
            Compile(obj[i], obj)
        end
    end,
    ['ifblock'] = function (obj)
        local lastBlock = Block
        Block = obj
        Compile(obj.filter, obj)
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['elseifblock'] = function (obj)
        local lastBlock = Block
        Block = obj
        Compile(obj.filter, obj)
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['elseblock'] = function (obj)
        local lastBlock = Block
        Block = obj
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['loop'] = function (obj)
        local lastBlock = Block
        Block = obj
        Compile(obj.loc, obj)
        Compile(obj.max, obj)
        Compile(obj.step, obj)
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['in'] = function (obj)
        local lastBlock = Block
        Block = obj
        local keys = obj.keys
        for i = 1, #keys do
            Compile(keys[i], obj)
        end
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['while'] = function (obj)
        local lastBlock = Block
        Block = obj
        Compile(obj.filter, obj)
        CompileBlock(obj, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['repeat'] = function (obj)
        local lastBlock = Block
        Block = obj
        CompileBlock(obj, obj)
        Compile(obj.filter, obj)
        if Block.locals then
            LocalCount = LocalCount - #Block.locals
        end
        Block = lastBlock
    end,
    ['break'] = function (obj)
        local block = guide.getBreakBlock(obj)
        if block then
            if not block.breaks then
                block.breaks = {}
            end
            block.breaks[#block.breaks+1] = obj
        else
            PushError {
                type   = 'BREAK_OUTSIDE',
                start  = obj.start,
                finish = obj.finish,
            }
        end
        if Block and Block[#Block] ~= obj then
            PushError {
                type   = 'ACTION_AFTER_BREAK',
                start  = obj.start,
                finish = obj.finish,
            }
        end
    end,
    ['continue'] = function (obj)
        local block = guide.getBreakBlock(obj)
        if block then
            if not block.breaks then
                block.breaks = {}
            end
            block.breaks[#block.breaks+1] = obj
        else
            PushError {
                type   = 'CONTINUE_OUTSIDE',
                start  = obj.start,
                finish = obj.finish,
            }
        end
        if Block and Block[#Block] ~= obj then
            PushError {
                type   = 'ACTION_AFTER_CONTINUE',
                start  = obj.start,
                finish = obj.finish,
            }
        end
    end,
    ['main'] = function (obj)
        Block = obj
        Compile({
            type   = 'local',
            start  = 0,
            finish = 0,
            effect = 0,
            tag    = '_ENV',
            special= '_G',
            [1]    = ENVMode,
        }, obj)
        --- _ENV 是上值，不计入局部变量计数
        LocalCount = 0
        CompileBlock(obj, obj)
        Block = nil
    end,
}

function CompileBlock(obj, parent)
    for i = 1, #obj do
        local act = obj[i]
        local f = vmMap[act.type]
        if f then
            act.parent = parent
            f(act)
        end
    end
end

function Compile(obj, parent)
    if not obj then
        return nil
    end
    if Compiled[obj] then
        return
    end
    Compiled[obj] = true
    obj.parent = parent
    local f = vmMap[obj.type]
    if not f then
        return
    end
    f(obj)
end

return function (self, lua, mode, uri)
    local state, err = self:parse(lua, mode)
    if not state then
        return nil, err
    end
    local clock = os.clock()
    PushError = state.pushError
    ENVMode = '@fenv'
    Compiled = {}
    LocalCount = 0
    Root = state.ast
    if Root then
        Root.state = state
    end
    Uri = uri
    Text = lua
    state.ENVMode = ENVMode
    if type(state.ast) == 'table' then
        Compile(state.ast)
    end
    state.compileClock = os.clock() - clock
    Compiled = nil
    return state
end
