local tonumber    = tonumber
local type        = type
local stringChar  = string.char
local utf8Char    = utf8.char
local tableUnpack = table.unpack
local mathType    = math.type
local tableRemove = table.remove
local pairs       = pairs
local ipairs      = ipairs
local tableSort   = table.sort
local output      = output

_ENV = nil

local DefaultState = {
    lua = '',
    options = {},
}

local State = DefaultState
local PushError
local PushDiag
local PushComment

-- goto 单独处理
local RESERVED = {
    ['and']      = true,
    ['break']    = true,
    ['do']       = true,
    ['else']     = true,
    ['elseif']   = true,
    ['end']      = true,
    ['false']    = true,
    ['for']      = true,
    ['function'] = true,
    ['if']       = true,
    ['in']       = true,
    ['local']    = true,
    ['nil']      = true,
    ['not']      = true,
    ['or']       = true,
    ['repeat']   = true,
    ['return']   = true,
    ['then']     = true,
    ['true']     = true,
    ['until']    = true,
    ['while']    = true,
}

local function checkMissEnd(start)
    if not State.MissEndErr then
        return
    end
    local err = State.MissEndErr
    State.MissEndErr = nil
    local _, finish = State.lua:find('[%w_]+', start)
    if not finish then
        return
    end
    err.info.related = {
        {
            start  = start,
            finish = finish,
        }
    }
    PushError {
        type   = 'MISS_END',
        start  = start,
        finish = finish,
    }
end

local function getSelect(vararg, index)
    return {
        type   = 'select',
        start  = vararg.start,
        finish = vararg.finish,
        vararg = vararg,
        index  = index
    }
end

local function getValue(values, i)
    if not values then
        return nil, nil
    end
    local value = values[i]
    if not value then
        local last = values[#values]
        if not last then
            return nil, nil
        end
        if last.type == 'call' or last.type == 'varargs' then
            return getSelect(last, i - #values + 1)
        end
        return nil, nil
    end
    if value.type == 'call' or value.type == 'varargs' then
        value = getSelect(value, 1)
    end
    return value
end

local function tableCopy(source, target)
    local mark = {}
    local function copy(a, b)
        if type(a) ~= 'table' then
            return a
        end
        if mark[a] then
            return mark[a]
        end
        if not b then
            b = {}
        end
        mark[a] = b
        for k, v in pairs(a) do
            b[copy(k)] = copy(v)
        end
        return b
    end
    return copy(source, target)
end

local function createLocal(key, effect, value, typeAnn)
    if not key then
        return nil
    end
    key.type   = 'local'
    key.effect = effect
    key.value  = value
    key.typeAnn = typeAnn
    if value then
        key.range = value.finish
    elseif typeAnn then
        key.range = typeAnn.finish
    end
    return key
end

local function createCall(args, start, finish)
    if args then
        args.type    = 'callargs'
        args.start   = start
        args.finish  = finish
    end
    return {
        type   = 'call',
        start  = start,
        finish = finish,
        args   = args,
    }
end

local function packList(start, list, finish)
    local lastFinish = start
    local wantName = true
    local count = 0
    for i = 1, #list do
        local ast = list[i]
        if ast.type == ',' then
            if wantName or i == #list then
                PushError {
                    type   = 'UNKNOWN_SYMBOL',
                    start  = ast.start,
                    finish = ast.finish,
                    info = {
                        symbol = ',',
                    }
                }
            end
            wantName = true
        elseif ast.type == "type.ann" then
            count = count + 1
            list[count] = list[i]
        else
            if not wantName then
                PushError {
                    type   = 'MISS_SYMBOL',
                    start  = lastFinish,
                    finish = ast.start - 1,
                    info = {
                        symbol = ',',
                    }
                }
            end
            wantName = false
            count = count + 1
            list[count] = list[i]
        end
        lastFinish = ast.finish + 1
    end
    for i = count + 1, #list do
        list[i] = nil
    end
    list.type   = 'list'
    list.start  = start
    list.finish = finish - 1
    return list
end

local BinaryLevel = {
    ['or']  = 1,
    ['and'] = 2,
    ['<=']  = 3,
    ['>=']  = 3,
    ['<']   = 3,
    ['>']   = 3,
    ['~=']  = 3,
    ['==']  = 3,
    ['..']  = 8,
    ['+']   = 9,
    ['-']   = 9,
    ['*']   = 10,
    ['/']   = 10,
    ['%']   = 10,
    ['^']   = 11,
}

local BinaryForward = {
    [01]  = true,
    [02]  = true,
    [03]  = true,
    [04]  = true,
    [05]  = true,
    [06]  = true,
    [07]  = true,
    [08]  = false,
    [09]  = true,
    [10]  = true,
    [11]  = false,
}

local Defs = {
    Nil = function (pos)
        return {
            type   = 'nil',
            start  = pos,
            finish = pos + 2,
        }
    end,
    True = function (pos)
        return {
            type   = 'boolean',
            start  = pos,
            finish = pos + 3,
            [1]    = true,
        }
    end,
    False = function (pos)
        return {
            type   = 'boolean',
            start  = pos,
            finish = pos + 4,
            [1]    = false,
        }
    end,
    ShortComment = function (start, text, finish)
        PushComment {
            type   = 'comment.short',
            start  = start,
            finish = finish - 1,
            text   = text,
        }
    end,
    LongComment = function (start, beforeEq, afterEq, str, close, finish)
        PushComment {
            type   = 'comment.long',
            start  = start,
            finish = finish - 1,
            text   = str,
        }
        if not close then
            local endSymbol = ']' .. ('='):rep(afterEq-beforeEq) .. ']'
            local s, _, w = str:find('(%][%=]*%])[%c%s]*$')
            if s then
                PushError {
                    type   = 'ERR_LCOMMENT_END',
                    start  = finish - #str + s - 1,
                    finish = finish - #str + s + #w - 2,
                    info   = {
                        symbol = endSymbol,
                    },
                    fix    = {
                        title = 'FIX_LCOMMENT_END',
                        {
                            start  = finish - #str + s - 1,
                            finish = finish - #str + s + #w - 2,
                            text   = endSymbol,
                        }
                    },
                }
            end
            PushError {
                type   = 'MISS_SYMBOL',
                start  = finish,
                finish = finish,
                info   = {
                    symbol = endSymbol,
                },
                fix    = {
                    title = 'ADD_LCOMMENT_END',
                    {
                        start  = finish,
                        finish = finish,
                        text   = endSymbol,
                    }
                },
            }
        end
    end,
    String = function (start, quote, str, finish)
        return {
            type   = 'string',
            start  = start,
            finish = finish - 1,
            [1]    = str,
            [2]    = quote,
        }
    end,
    LongString = function (beforeEq, afterEq, str, missPos)
        if missPos then
            local endSymbol = ']' .. ('='):rep(afterEq-beforeEq) .. ']'
            local s, _, w = str:find('(%][%=]*%])[%c%s]*$')
            if s then
                PushError {
                    type   = 'ERR_LSTRING_END',
                    start  = missPos - #str + s - 1,
                    finish = missPos - #str + s + #w - 2,
                    info   = {
                        symbol = endSymbol,
                    },
                    fix    = {
                        title = 'FIX_LSTRING_END',
                        {
                            start  = missPos - #str + s - 1,
                            finish = missPos - #str + s + #w - 2,
                            text   = endSymbol,
                        }
                    },
                }
            end
            PushError {
                type   = 'MISS_SYMBOL',
                start  = missPos,
                finish = missPos,
                info   = {
                    symbol = endSymbol,
                },
                fix    = {
                    title = 'ADD_LSTRING_END',
                    {
                        start  = missPos,
                        finish = missPos,
                        text   = endSymbol,
                    }
                },
            }
        end
        return '[' .. ('='):rep(afterEq-beforeEq) .. '[', str
    end,
    Char10 = function (char)
        char = tonumber(char)
        if not char or char < 0 or char > 255 then
            return ''
        end
        return stringChar(char)
    end,
    Char16 = function (pos, char)
        return stringChar(tonumber(char, 16))
    end,
    CharUtf8 = function (pos, char)
        if #char == 0 then
            PushError {
                type = 'UTF8_SMALL',
                start = pos-3,
                finish = pos,
            }
            return ''
        end
        local v = tonumber(char, 16)
        if not v then
            for i = 1, #char do
                if not tonumber(char:sub(i, i), 16) then
                    PushError {
                        type = 'MUST_X16',
                        start = pos + i - 1,
                        finish = pos + i - 1,
                    }
                end
            end
            return ''
        end
        if v < 0 or v > 0x7FFFFFFF then
            PushError {
                type = 'UTF8_MAX',
                start = pos-3,
                finish = pos+#char,
                info = {
                    min = '00000000',
                    max = '7FFFFFFF',
                }
            }
        end
        -- if v < 0 or v > 0x10FFFF then
        --     PushError {
        --         type = 'UTF8_MAX',
        --         start = pos-3,
        --         finish = pos+#char,
        --         version = v <= 0x7FFFFFFF and 'Lua 5.4' or nil,
        --         info = {
        --             min = '000000',
        --             max = '10FFFF',
        --         }
        --     }
        -- end
        if v >= 0 and v <= 0x10FFFF then
            return utf8Char(v)
        end
        return ''
    end,
    Number = function (start, number, finish)
        local n = tonumber(number)
        number = number:gsub("_", "")
        if number:sub(2, 2):lower() == "b" then
            n = tonumber(number:sub(3), 2)
        else
            n = tonumber(number)
        end
        if n then
            State.LastNumber = {
                type   = 'number',
                start  = start,
                finish = finish - 1,
                [1]    = n,
            }
            State.LastRaw = number
            return State.LastNumber
        else
            PushError {
                type   = 'MALFORMED_NUMBER',
                start  = start,
                finish = finish - 1,
            }
            State.LastNumber = {
                type   = 'number',
                start  = start,
                finish = finish - 1,
                [1]    = 0,
            }
            State.LastRaw = number
            return State.LastNumber
        end
    end,
    -- FFINumber = function (start, symbol)
    --     local lastNumber = State.LastNumber
    --     if State.LastRaw:find('.', 1, true) then
    --         PushError {
    --             type = 'UNKNOWN_SYMBOL',
    --             start = start,
    --             finish = start + #symbol - 1,
    --             info = {
    --                 symbol = symbol,
    --             }
    --         }
    --         lastNumber[1] = 0
    --         return
    --     end
    --     if State.version ~= 'LuaJIT' then
    --         PushError {
    --             type = 'UNSUPPORT_SYMBOL',
    --             start = start,
    --             finish = start + #symbol - 1,
    --             version = 'LuaJIT',
    --             info = {
    --                 version = State.version,
    --             }
    --         }
    --         lastNumber[1] = 0
    --     end
    -- end,
    -- ImaginaryNumber = function (start, symbol)
    --     local lastNumber = State.LastNumber
    --     if State.version ~= 'LuaJIT' then
    --         PushError {
    --             type = 'UNSUPPORT_SYMBOL',
    --             start = start,
    --             finish = start + #symbol - 1,
    --             version = 'LuaJIT',
    --             info = {
    --                 version = State.version,
    --             }
    --         }
    --     end
    --     lastNumber[1] = 0
    -- end,
    Name = function (start, str, finish)
        local isKeyWord
        if RESERVED[str] then
            isKeyWord = true
        end
        if isKeyWord then
            PushError {
                type = 'KEYWORD',
                start = start,
                finish = finish - 1,
            }
        end
        return {
            type   = 'name',
            start  = start,
            finish = finish - 1,
            [1]    = str,
        }
    end,
    GetField = function (dot, field)
        local obj = {
            type   = 'getfield',
            field  = field,
            dot    = dot,
            start  = dot.start,
            finish = (field or dot).finish,
        }
        if field then
            field.type = 'field'
            field.parent = obj
        end
        return obj
    end,
    GetIndex = function (start, index, finish)
        local obj = {
            type   = 'getindex',
            bstart = start,
            start  = start,
            finish = finish - 1,
            index  = index,
        }
        if index then
            index.parent = obj
        end
        return obj
    end,
    GetMethod = function (colon, method)
        local obj = {
            type   = 'getmethod',
            method = method,
            colon  = colon,
            start  = colon.start,
            finish = (method or colon).finish,
        }
        if method then
            method.type = 'method'
            method.parent = obj
        end
        return obj
    end,
    Single = function (unit)
        unit.type  = 'getname'
        return unit
    end,
    Simple = function (units)
        local last = units[1]
        for i = 2, #units do
            local current  = units[i]
            current.node = last
            current.start  = last.start
            last.next = current
            last = units[i]
        end
        return last
    end,
    SimpleCall = function (call)
        if call.type ~= 'call' and call.type ~= 'getmethod' then
            PushError {
                type   = 'EXP_IN_ACTION',
                start  = call.start,
                finish = call.finish,
            }
        end
        return call
    end,
    BinaryOp = function (start, op)
        return {
            type   = op,
            start  = start,
            finish = start + #op - 1,
        }
    end,
    UnaryOp = function (start, op)
        return {
            type   = op,
            start  = start,
            finish = start + #op - 1,
        }
    end,
    Unary = function (first, ...)
        if not ... then
            return nil
        end
        local list = {first, ...}
        local e = list[#list]
        for i = #list - 1, 1, -1 do
            local op = list[i]
            e = {
                type   = 'unary',
                op     = op,
                start  = op.start,
                finish = e.finish,
                [1]    = e,
            }
        end
        return e
    end,
    SubBinary = function (op, symb)
        if symb then
            return op, symb
        end
        PushError {
            type   = 'MISS_EXP',
            start  = op.start,
            finish = op.finish,
        }
    end,
    Binary = function (first, op, second, ...)
        if not first then
            return second
        end
        if not op then
            return first
        end
        if not ... then
            return {
                type   = 'binary',
                op     = op,
                start  = first.start,
                finish = second.finish,
                [1]    = first,
                [2]    = second,
            }
        end
        local list = {first, op, second, ...}
        local ops = {}
        for i = 2, #list, 2 do
            ops[#ops+1] = i
        end
        tableSort(ops, function (a, b)
            local op1 = list[a]
            local op2 = list[b]
            local lv1 = BinaryLevel[op1.type]
            local lv2 = BinaryLevel[op2.type]
            if lv1 == lv2 then
                local forward = BinaryForward[lv1]
                if forward then
                    return op1.start > op2.start
                else
                    return op1.start < op2.start
                end
            else
                return lv1 < lv2
            end
        end)
        local final
        for i = #ops, 1, -1 do
            local n     = ops[i]
            local op    = list[n]
            local left  = list[n-1]
            local right = list[n+1]
            local exp = {
                type   = 'binary',
                op     = op,
                start  = left.start,
                finish = right and right.finish or op.finish,
                [1]    = left,
                [2]    = right,
            }
            local leftIndex, rightIndex
            if list[left] then
                leftIndex = list[left[1]]
            else
                leftIndex = n - 1
            end
            if list[right] then
                rightIndex = list[right[2]]
            else
                rightIndex = n + 1
            end

            list[leftIndex]  = exp
            list[rightIndex] = exp
            list[left]       = leftIndex
            list[right]      = rightIndex
            list[exp]        = n
            final = exp
        end
        return final
    end,
    Paren = function (start, exp, finish)
        if exp and exp.type == 'paren' then
            exp.start  = start
            exp.finish = finish - 1
            return exp
        end
        return {
            type   = 'paren',
            start  = start,
            finish = finish - 1,
            exp    = exp
        }
    end,
    VarArgs = function (dots)
        dots.type = 'varargs'
        return dots
    end,
    PackLoopArgs = function (start, list, finish)
        local list = packList(start, list, finish)
        if #list == 0 then
            PushError {
                type   = 'MISS_LOOP_MIN',
                start  = finish,
                finish = finish,
            }
        elseif #list == 1 then
            PushError {
                type   = 'MISS_LOOP_MAX',
                start  = finish,
                finish = finish,
            }
        end
        return list
    end,
    PackInNameList = function (start, list, finish)
        local list = packList(start, list, finish)
        if #list == 0 then
            PushError {
                type   = 'MISS_NAME',
                start  = start,
                finish = finish,
            }
        end
        return list
    end,
    PackInExpList = function (start, list, finish)
        local list = packList(start, list, finish)
        if #list == 0 then
            PushError {
                type   = 'MISS_EXP',
                start  = start,
                finish = finish,
            }
        end
        return list
    end,
    PackExpList = function (start, list, finish)
        local list = packList(start, list, finish)
        return list
    end,
    PackNameList = function (start, list, finish)
        local list = packList(start, list, finish)
        return list
    end,
    Call = function (start, args, finish)
        return createCall(args, start, finish-1)
    end,
    IfExp = function (ifStart, ifFinish, ifExp, thenStart, thenFinish, thenExp, elseIfs, elseStart, elseFinish, elseExp, finish)
        local obj = {
            type   = 'ifexp',
            start  = ifStart,
            finish = finish,
            keyword = {
                ifStart, ifFinish - 1,
                thenStart, thenFinish - 1,
                elseStart, elseFinish - 1,
            },
            filter = ifExp,
            [1]    = thenExp,
        }
        for i = 1, #elseIfs do
            obj[#obj+1] = elseIfs[i]
        end
        obj[#obj+1] = elseExp
        return obj
    end,
    ElseIfExp = function(ifStart, ifFinish, ifExp, thenStart, thenFinsih, thenExp, finish)
        return {
            type   = 'elseifexp',
            start  = ifStart,
            finish = finish,
            keyword = {
                ifStart, ifFinish - 1,
                thenStart, thenFinsih - 1,
            },
            filter = ifExp,
            [1]    = thenExp,
        }
    end,
    TypeSimple = function (units, optional)
        local last = units[1]
        for i = 2, #units do
            local current  = units[i]
            current.node = last
            current.start  = last.start
            last.next = current
            last = units[i]
        end
        last.optional = optional or last.optional
        return last
    end,
    Type = function (...)
        local units = {...}
        if #units <= 2 then
            return units[1]
        end
        local list = {
            start = units[1].start,
            finish = units[#units].finish
        }
        for _, unit in ipairs(units) do
            if unit.type == "|" then
                if list.type and list.type ~= "type.union" then
                    PushError {
                        type   = 'MIX_UNION_INTER',
                        start  = list.start,
                        finish = list.finish,
                    }
                    break
                end
                list.type = "type.union"
            elseif unit.type == "&" then
                if list.type and list.type ~= "type.inter" then
                    PushError {
                        type   = 'MIX_UNION_INTER',
                        start  = list.start,
                        finish = list.finish,
                    }
                    break
                end
                list.type = "type.inter"
            else
                if unit.optional and list.type ~= "type.union" then
                    PushError {
                        type   = 'MIX_UNION_INTER',
                        start  = list.start,
                        finish = list.finish,
                    }
                    break
                end
                list[#list+1] = unit
            end
        end
        return list
    end,
    SubType = function (op, symb)
        if symb then
            return op, symb
        end
        PushError {
            type   = 'MISS_TYPE',
            start  = op.start,
            finish = op.finish,
        }
    end,
    NameType = function (start, str, generics, finish, optional)
        if str ~= "nil" and RESERVED[str] then
            PushError {
                type   = 'KEYWORD',
                start  = start,
                finish = finish,
            }
        end
        return {
            type   = 'type.name',
            start  = start,
            finish = finish - 1,
            generics = generics,
            optional = optional,
            [1]    = str,
        }
    end,
    ModuleType = function (start, str1, dot, nameType, finish, optional)
        if not nameType then
            PushError {
                type   = 'MISS_TYPE',
                start  = start,
                finish = finish,
            }
            nameType = {
                type = "type.name",
                [1] = "",
                start = start,
                finish = dot.finish,
            }
        end
        return {
            type   = 'type.module',
            start  = start,
            finish = finish - 1,
            dot    = dot,
            optional = optional,
            [1]    = str1,
            [2]    = nameType
        }
    end,
    FuncType = function (start, generics, args, returns, optional, finish)
        args.funcargs = true
        return {
            type = "type.function",
            start = start,
            finish = finish or optional,
            args = args,
            returns = returns,
            generics = generics,
            optional = finish and optional
        }
    end,
    TableType = function (start, fields, finish, optional)
        local wantType = true
        local lastStart = start + 1
        local types = {}
        for i = 1, #fields do
            local v = fields[i]
            if v and v.type then
                if v.type == "," or v.type == ";" then
                    if wantType then
                        PushError {
                            type = 'MISS_FIELD',
                            start = lastStart,
                            finish = v.start-1,
                        }
                    end
                    wantType = true
                else
                    if not wantType then
                        PushError {
                            type = 'MISS_SYMBOL',
                            start = lastStart-1,
                            finish = v.start-1,
                            info = {
                                symbol = ',',
                            }
                        }
                    end
                    types[#types+1] = v
                    wantType = false
                end
                lastStart = (v.range or v.finish) + 1
            end
        end
        return {
            type = "type.table",
            start = start,
            finish = finish,
            optional = optional,
            tableUnpack(types)
        }
    end,
    VariadicType = function (start, dots, type, finish)
        return {
            type = "type.variadic",
            start = start,
            finish = finish,
            dots = dots,
            value = type
        }
    end,
    NamedType = function (key, colon, value)
        value.paramName = key
        return value
    end,
    FieldType = function (start, key, colon, value, finish)
        key.type = "type.field.key"
        return {
            type = "type.field",
            colon = colon,
            start = start,
            finish = finish,
            key = key,
            value = value,
            range = finish
        }
    end,
    IndexType = function (start, key, colon, value, finish)
        return {
            type = "type.index",
            colon = colon,
            start = start,
            finish = finish,
            key = key,
            value = value
        }
    end,
    FieldTypeList = function (list)
        local hasIndexer = false
        for _, field in pairs(list) do
            if field.type == "type.index" then
                if hasIndexer then
                    PushError {
                        type = 'MULTIPLE_TABLE_INDEXER',
                        start = field.start,
                        finish = field.finish,
                    }
                else
                    hasIndexer = true
                end
            elseif field.type ~= "," and field.type ~= ";" and field.type ~= "type.field" and #list > 1 then
                PushError {
                    type = 'EXPECTED_FIELD_COLON',
                    start = field.finish + 1,
                    finish = field.finish + 1,
                }
            end
        end
        return list
    end,
    TypeList = function(start, list, finish)
        local wantType = true
        local lastStart = start + 1
        local lastComma = nil
        local types = {}
        for i = 1, #list do
            local v = list[i]
            if v.type == "," then
                lastComma = v.start
                if wantType then
                    PushError {
                        type = 'MISS_TYPE',
                        start = lastStart,
                        finish = v.start-1,
                    }
                end
                wantType = true
            else
                if not wantType then
                    PushError {
                        type = 'MISS_SYMBOL',
                        start = lastStart-1,
                        finish = v.start-1,
                        info = {
                            symbol = ',',
                        }
                    }
                end
                if v.type == "type.variadic" then
                    if i < #list then
                        local a = list[#list - 1]
                        local b = list[#list]
                        PushError {
                            type = 'ARGS_AFTER_DOTS',
                            start = type(a) == 'number' and a or a.start,
                            finish = type(b) == 'number' and b or b.finish,
                        }
                    end
                end
                types[#types+1] = v
                wantType = false
            end
            lastStart = v.finish + 1
        end
        if wantType and lastComma then
            PushError {
                type   = 'UNEXPECT_SYMBOL',
                start  = lastComma,
                finish = lastComma,
                info   = {
                    symbol = ',',
                }
            }
        end
        return {
            type = "type.list",
            start = start,
            finish = finish,
            tableUnpack(types)
        }
    end,
    TypeAnn = function(colon, start, type, finish)
        return {
            type = "type.ann",
            start = start,
            finish = finish,
            colon = colon,
            value = type
        }
    end,
    Optional = function()
        return true
    end,
    TypeAssert = function (exp, type)
        if exp and type then
            return {
                type = "type.assert",
                start = exp.start,
                finish = type.finish,
                exp,
                type
            }
        end
        return exp
    end,
    Generics = function(start, list, finish)
        local wantType = true
        local lastStart = start + 1
        local generics = {}
        for i = 1, #list do
            local v = list[i]
            if v.type == "," then
                if wantType then
                    PushError {
                        type = 'MISS_TYPE',
                        start = lastStart,
                        finish = v.start-1,
                    }
                end
                wantType = true
            else
                if not wantType then
                    PushError {
                        type = 'MISS_SYMBOL',
                        start = lastStart-1,
                        finish = v.start-1,
                        info = {
                            symbol = ',',
                        }
                    }
                end
                if v.type == "name" then
                    v.type = "type.parameter"
                    v.replace = {}
                end
                generics[#generics+1] = v
                wantType = false
            end
            lastStart = v.finish + 1
        end
        if wantType and #generics > 0 then
            PushError {
                type = 'MISS_TYPE',
                start = lastStart,
                finish = finish - 1,
            }
        end
        return {
            type = "type.generics",
            start = start,
            finish = finish,
            tableUnpack(generics)
        }
    end,
    Typeof = function(start, expStart, exp, finish, optional)
        local obj = {
            type = "type.typeof",
            start = start,
            finish = finish,
            optional = optional,
            name = {
                type = "name",
                start = start,
                finish = start + #"typeof",
                [1] = "typeof"
            },
            call = {
                type = "call",
                start = start + #"typeof",
                finish = finish,
            },
            value = exp
        }
        return obj
    end,
    TypeAlias = function (start, export, name, generics, type, finish)
        if name[1]:match("%.") then
            PushError {
                type = 'EXP_IN_ACTION',
                start = name.start,
                finish = name.finish,
            }
        end
        name.type = "type.alias.name"
        return {
            type = "type.alias",
            export = export,
            start = start,
            name = name,
            finish = finish,
            generics = generics,
            value = type,
            effect = finish
        }
    end,
    COMMA = function (start)
        return {
            type   = ',',
            start  = start,
            finish = start,
        }
    end,
    SEMICOLON = function (start)
        return {
            type   = ';',
            start  = start,
            finish = start,
        }
    end,
    DOTS = function (start)
        return {
            type   = '...',
            start  = start,
            finish = start + 2,
        }
    end,
    COLON = function (start)
        return {
            type   = ':',
            start  = start,
            finish = start,
        }
    end,
    DOT = function (start)
        return {
            type   = '.',
            start  = start,
            finish = start,
        }
    end,
    Function = function (functionStart, functionFinish, name, generics, args, argsFinish, typeAnn, actions, endStart, endFinish)
        actions.type   = 'function'
        actions.start  = functionStart
        actions.finish = endFinish - 1
        actions.args   = args
        actions.generics = generics
        actions.argsFinish = argsFinish - 1
        actions.keyword= {
            functionStart, functionFinish - 1,
            endStart,      endFinish - 1,
        }
        actions.returnTypeAnn = typeAnn
        checkMissEnd(functionStart)
        if not name then
            return actions
        end
        if name.type == 'getname' then
            name.type = 'setname'
            name.value = actions
        elseif name.type == 'getfield' then
            name.type = 'setfield'
            name.value = actions
        elseif name.type == 'getmethod' then
            name.type = 'setmethod'
            name.value = actions
        elseif name.type == 'getindex' then
            name.type = 'setfield'
            name.value = actions
            PushError {
                type = 'INDEX_IN_FUNC_NAME',
                start = name.bstart,
                finish = name.finish,
            }
        end
        name.range = actions.finish
        name.vstart = functionStart
        return name
    end,
    NamedFunction = function (name)
        if name.type == 'function' then
            PushError {
                type = 'MISS_NAME',
                start = name.keyword[2] + 1,
                finish = name.keyword[2] + 1,
            }
        end
        return name
    end,
    LocalFunction = function (start, name)
        if name.type == 'function' then
            PushError {
                type = 'MISS_NAME',
                start = name.keyword[2] + 1,
                finish = name.keyword[2] + 1,
        }
            return name
        end
        if name.type ~= 'setname' then
            PushError {
                type = 'UNEXPECT_LFUNC_NAME',
                start = name.start,
                finish = name.finish,
            }
            return name
        end

        local loc = createLocal(name, name.start, name.value)
        loc.localfunction = true
        loc.vstart = name.value.start
        return name
    end,
    ExpFunction = function (func)
        if func.type ~= 'function' then
            PushError {
                type = 'UNEXPECT_EFUNC_NAME',
                start = func.start,
                finish = func.finish,
            }
            return func.value
        end
        return func
    end,
    Table = function (start, tbl, finish)
        tbl.type   = 'table'
        tbl.start  = start
        tbl.finish = finish - 1
        local wantField = true
        local lastStart = start + 1
        local fieldCount = 0
        for i = 1, #tbl do
            local field = tbl[i]
            if field.type == ',' or field.type == ';' then
                if wantField then
                    PushError {
                        type = 'MISS_EXP',
                        start = lastStart,
                        finish = field.start - 1,
                    }
                end
                wantField = true
                lastStart = field.finish + 1
            else
                if not wantField then
                    PushError {
                        type = 'MISS_SEP_IN_TABLE',
                        start = lastStart,
                        finish = field.start - 1,
                    }
                end
                wantField = false
                lastStart = field.finish + 1
                fieldCount = fieldCount + 1
                tbl[fieldCount] = field
            end
        end
        for i = fieldCount + 1, #tbl do
            tbl[i] = nil
        end
        return tbl
    end,
    NewField = function (start, field, value, finish)
        local obj = {
            type   = 'tablefield',
            start  = start,
            finish = finish-1,
            field  = field,
            value  = value,
        }
        if field then
            field.type = 'field'
            field.parent = obj
        end
        return obj
    end,
    NewIndex = function (start, index, value, finish)
        local obj = {
            type   = 'tableindex',
            start  = start,
            finish = finish-1,
            index  = index,
            value  = value,
        }
        if index then
            index.parent = obj
        end
        return obj
    end,
    FuncArgs = function (start, args, finish)
        args.type   = 'funcargs'
        args.start  = start
        args.finish = finish - 1
        local lastStart = start + 1
        local wantName = true
        local argCount = 0
        for i = 1, #args do
            local arg = args[i]
            local argAst = arg
            if argAst.type == ',' then
                if wantName then
                    PushError {
                        type = 'MISS_NAME',
                        start = lastStart,
                        finish = argAst.start-1,
                    }
                end
                wantName = true
            elseif argAst.type == "type.ann" then
                goto CONTINUE
            else
                if not wantName then
                    PushError {
                        type = 'MISS_SYMBOL',
                        start = lastStart-1,
                        finish = argAst.start-1,
                        info = {
                            symbol = ',',
                        }
                    }
                end
                wantName = false
                argCount = argCount + 1

                if argAst.type == '...' then
                    args[argCount] = arg
                    if i < #args then
                        local a = args[i+1]
                        local b = args[#args]
                        if type(b) ~= "number" and b.type == "type.ann" then
                            arg.typeAnn = b
                            arg.range = b.finish
                            break
                        end
                        PushError {
                            type   = 'ARGS_AFTER_DOTS',
                            start  = a.start,
                            finish = b.finish,
                        }
                    end
                    break
                else
                    local typeAnn = args[i + 1]
                    if typeAnn and typeAnn.type ~= "type.ann" then
                        typeAnn = nil
                    end
                    args[argCount] = createLocal(arg, arg.start, nil, typeAnn)
                end
            end
            lastStart = argAst.finish + 1
            ::CONTINUE::
        end
        for i = argCount + 1, #args do
            args[i] = nil
        end
        if wantName and argCount > 0 then
            PushError {
                type   = 'MISS_NAME',
                start  = lastStart,
                finish = finish - 1,
            }
        end
        return args
    end,
    CompOp = function (start, op, finish)
        return {
            type = op,
            start = start,
            finish = finish + 1
        }
    end,
    CompSet = function (start, keys, op, eqFinish, values, finish)
        if #keys > 1 then
            PushError {
                type   = 'MULTI_VAR_ASSIGN',
                start  = op.start,
                finish = op.finish,
            }
        end
        if values[1] then
            local value = {
                [1] = tableCopy(keys[1]),
                [2] = values[1],
                type = "binary",
                start = values[1].start,
                finish = values[1].finish,
                op = op,
            }
            values[1] = value
        end
        for i = 1, #keys do
            local key = keys[i]
            if key.type == 'getname' then
                key.type = 'setname'
                key.value = getValue(values, i)
            elseif key.type == 'getfield' then
                key.type = 'setfield'
                key.value = getValue(values, i)
            elseif key.type == 'getindex' then
                key.type = 'setindex'
                key.value = getValue(values, i)
            else
                PushError {
                    type   = 'UNEXPECT_SYMBOL',
                    start  = eqFinish - 1,
                    finish = eqFinish - 1,
                    info   = {
                        symbol = '=',
                    }
                }
            end
            if key.value then
                key.range = key.value.finish
            end
        end
        if values then
            for i = #keys+1, #values do
                local value = values[i]
                PushDiag('redundant-value', {
                    start  = value.start,
                    finish = value.finish,
                    max    = #keys,
                    passed = #values,
                })
            end
        end
        return tableUnpack(keys)
    end,
    Set = function (start, keys, eqFinish, values, finish)
        for i = 1, #keys do
            local key = keys[i]
            if key.type == 'getname' then
                key.type = 'setname'
                key.value = getValue(values, i)
            elseif key.type == 'getfield' then
                key.type = 'setfield'
                key.value = getValue(values, i)
            elseif key.type == 'getindex' then
                key.type = 'setindex'
                key.value = getValue(values, i)
            else
                PushError {
                    type   = 'UNEXPECT_SYMBOL',
                    start  = eqFinish - 1,
                    finish = eqFinish - 1,
                    info   = {
                        symbol = '=',
                    }
                }
            end
            if key.value then
                key.range = key.value.finish
            end
        end
        if values then
            for i = #keys+1, #values do
                local value = values[i]
                PushDiag('redundant-value', {
                    start  = value.start,
                    finish = value.finish,
                    max    = #keys,
                    passed = #values,
                })
            end
        end
        return tableUnpack(keys)
    end,
    LocalName = function (name, typeAnn)
        if not name then
            return
        end
        name.typeAnn = typeAnn
        return name
    end,
    Local = function (start, keys, values, finish)
        for i, key in ipairs(keys) do
            local typeAnn = key.typeAnn
            key.typeAnn = nil
            local value = getValue(values, i)
            createLocal(key, finish, value, typeAnn)
        end
        if values then
            for i = #keys+1, #values do
                local value = values[i]
                PushDiag('redundant-value', {
                    start  = value.start,
                    finish = value.finish,
                    max    = #keys,
                    passed = #values,
                })
            end
        end
        return tableUnpack(keys)
    end,
    Do = function (start, actions, endA, endB)
        actions.type = 'do'
        actions.start  = start
        actions.finish = endB - 1
        actions.keyword= {
            start, start + #'do' - 1,
            endA , endB - 1,
        }
        checkMissEnd(start)
        return actions
    end,
    Break = function (start, finish)
        return {
            type   = 'break',
            start  = start,
            finish = finish - 1,
        }
    end,
    Continue = function (start, finish, ...)
        return {
            type   = 'continue',
            start  = start,
            finish = finish - 1,
        }
    end,
    Return = function (start, exps, finish)
        exps.type   = 'return'
        exps.start  = start
        exps.finish = finish - 1
        return exps
    end,
    IfBlock = function (ifStart, ifFinish, exp, thenStart, thenFinish, actions, finish)
        actions.type   = 'ifblock'
        actions.start  = ifStart
        actions.finish = finish - 1
        actions.filter = exp
        actions.keyword= {
            ifStart,   ifFinish - 1,
            thenStart, thenFinish - 1,
        }
        return actions
    end,
    ElseIfBlock = function (elseifStart, elseifFinish, exp, thenStart, thenFinish, actions, finish)
        actions.type   = 'elseifblock'
        actions.start  = elseifStart
        actions.finish = finish - 1
        actions.filter = exp
        actions.keyword= {
            elseifStart, elseifFinish - 1,
            thenStart,   thenFinish - 1,
        }
        return actions
    end,
    ElseBlock = function (elseStart, elseFinish, actions, finish)
        actions.type   = 'elseblock'
        actions.start  = elseStart
        actions.finish = finish - 1
        actions.keyword= {
            elseStart, elseFinish - 1,
        }
        return actions
    end,
    If = function (start, blocks, endStart, endFinish)
        blocks.type   = 'if'
        blocks.start  = start
        blocks.finish = endFinish - 1
        local hasElse
        for i = 1, #blocks do
            local block = blocks[i]
            if i == 1 and block.type ~= 'ifblock' then
                PushError {
                    type = 'MISS_SYMBOL',
                    start = block.start,
                    finish = block.start,
                    info = {
                        symbol = 'if',
                    }
                }
            end
            if hasElse then
                PushError {
                    type   = 'BLOCK_AFTER_ELSE',
                    start  = block.start,
                    finish = block.finish,
                }
            end
            if block.type == 'elseblock' then
                hasElse = true
            end
        end
        checkMissEnd(start)
        return blocks
    end,
    Loop = function (forA, forB, arg, steps, doA, doB, blockStart, block, endA, endB)
        local loc = createLocal(arg, blockStart, steps[1])
        block.type   = 'loop'
        block.start  = forA
        block.finish = endB - 1
        block.loc    = loc
        block.max    = steps[2]
        block.step   = steps[3]
        block.keyword= {
            forA, forB - 1,
            doA , doB  - 1,
            endA, endB - 1,
        }
        checkMissEnd(forA)
        return block
    end,
    In = function (forA, forB, keys, inA, inB, exp, doA, doB, blockStart, block, endA, endB)
        local func = tableRemove(exp, 1)
        block.type   = 'in'
        block.start  = forA
        block.finish = endB - 1
        block.keys   = keys
        block.keyword= {
            forA, forB - 1,
            inA , inB  - 1,
            doA , doB  - 1,
            endA, endB - 1,
        }

        local values
        if func then
            local call = createCall(exp, func.finish + 1, exp.finish)
            call.node = func
            call.start = func.start
            call.nocheck = true
            func.next = call
            func.iterator = true
            values = { call }
            keys.range = call.finish
        end
        for i, key in ipairs(keys) do
            local typeAnn = keys[i + 1]
            if typeAnn and typeAnn.type == "type.ann" then
                tableRemove(keys, i + 1)
            else
                typeAnn = nil
            end
            if values then
                createLocal(key, blockStart, getValue(values, i), typeAnn)
            else
                createLocal(key, blockStart, nil, typeAnn)
            end
        end
        checkMissEnd(forA)
        return block
    end,
    While = function (whileA, whileB, filter, doA, doB, block, endA, endB)
        block.type   = 'while'
        block.start  = whileA
        block.finish = endB - 1
        block.filter = filter
        block.keyword= {
            whileA, whileB - 1,
            doA   , doB    - 1,
            endA  , endB   - 1,
        }
        checkMissEnd(whileA)
        return block
    end,
    Repeat = function (repeatA, repeatB, block, untilA, untilB, filter, finish)
        block.type   = 'repeat'
        block.start  = repeatA
        block.finish = finish
        block.filter = filter
        block.keyword= {
            repeatA, repeatB - 1,
            untilA , untilB  - 1,
        }
        return block
    end,
    Lua = function (start, actions, finish)
        actions.type   = 'main'
        actions.start  = start
        actions.finish = finish - 1
        return actions
    end,

    -- 捕获错误
    UnknownSymbol = function (start, symbol)
        PushError {
            type = 'UNKNOWN_SYMBOL',
            start = start,
            finish = start + #symbol - 1,
            info = {
                symbol = symbol,
            }
        }
        return
    end,
    UnknownAction = function (start, symbol)
        PushError {
            type = 'UNKNOWN_SYMBOL',
            start = start,
            finish = start + #symbol - 1,
            info = {
                symbol = symbol,
            }
        }
    end,
    DirtyName = function (pos)
        PushError {
            type = 'MISS_NAME',
            start = pos,
            finish = pos,
        }
        return nil
    end,
    DirtyExp = function (pos)
        PushError {
            type = 'MISS_EXP',
            start = pos,
            finish = pos,
        }
        return nil
    end,
    DirtyType = function (pos)
        PushError {
            type = 'MISS_TYPE',
            start = pos,
            finish = pos,
        }
        return {
            [1] = "",
            start = pos,
            finish = pos,
            type = "type.name"
        }
    end,
    MissExp = function (pos)
        PushError {
            type = 'MISS_EXP',
            start = pos,
            finish = pos,
        }
    end,
    MissExponent = function (start, finish)
        PushError {
            type = 'MISS_EXPONENT',
            start = start,
            finish = finish - 1,
        }
    end,
    MissQuote1 = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '"'
            }
        }
    end,
    MissQuote2 = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = "'"
            }
        }
    end,
    MissEscX = function (pos)
        PushError {
            type = 'MISS_ESC_X',
            start = pos-2,
            finish = pos+1,
        }
    end,
    MissTL = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '{',
            }
        }
    end,
    MissTR = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '}',
            }
        }
    end,
    MissBR = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = ']',
            }
        }
    end,
    MissPL = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '(',
            }
        }
    end,
    MissPR = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = ')',
            }
        }
    end,
    MissAR = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '>',
            }
        }
    end,
    ErrEsc = function (pos)
        PushError {
            type = 'ERR_ESC',
            start = pos-1,
            finish = pos,
        }
    end,
    MustX16 = function (pos, str)
        PushError {
            type = 'MUST_X16',
            start = pos,
            finish = pos + #str - 1,
        }
    end,
    MustX2 = function (pos, str)
        PushError {
            type = 'MUST_X2',
            start = pos,
            finish = pos + #str - 1,
        }
    end,
    MissAssign = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = '=',
            }
        }
    end,
    MissTableSep = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = ','
            }
        }
    end,
    MissField = function (pos)
        PushError {
            type = 'MISS_FIELD',
            start = pos,
            finish = pos,
        }
    end,
    MissMethod = function (pos)
        PushError {
            type = 'MISS_METHOD',
            start = pos,
            finish = pos,
        }
    end,
    MissEnd = function (pos)
        State.MissEndErr = PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'end',
            }
        }
        return pos, pos
    end,
    MissDo = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'do',
            }
        }
        return pos, pos
    end,
    MissComma = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = ',',
            }
        }
    end,
    MissIn = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'in',
            }
        }
        return pos, pos
    end,
    MissUntil = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'until',
            }
        }
        return pos, pos
    end,
    MissThen = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'then',
            }
        }
        return pos, pos
    end,
    MissElse = function (pos)
        PushError {
            type = 'MISS_SYMBOL',
            start = pos,
            finish = pos,
            info = {
                symbol = 'else',
            }
        }
        return pos, pos
    end,
    MissName = function (pos)
        PushError {
            type = 'MISS_NAME',
            start = pos,
            finish = pos,
        }
    end,
    ExpInAction = function (start, exp, finish)
        PushError {
            type = 'EXP_IN_ACTION',
            start = start,
            finish = finish - 1,
        }
        -- 当exp为nil时，不能返回任何值，否则会产生带洞的actionlist
        if exp then
            return exp
        else
            return
        end
    end,
    MissIf = function (start, block)
        PushError {
            type = 'MISS_SYMBOL',
            start = start,
            finish = start,
            info = {
                symbol = 'if',
            }
        }
        return block
    end,
    ErrAssign = function (start, finish)
        PushError {
            type = 'ERR_ASSIGN_AS_EQ',
            start = start,
            finish = finish - 1,
            fix = {
                title = 'FIX_ASSIGN_AS_EQ',
                {
                    start   = start,
                    finish  = finish - 1,
                    text    = '=',
                }
            }
        }
    end,
    ErrEQ = function (start, finish)
        PushError {
            type   = 'ERR_EQ_AS_ASSIGN',
            start  = start,
            finish = finish - 1,
            fix = {
                title = 'FIX_EQ_AS_ASSIGN',
                {
                    start  = start,
                    finish = finish - 1,
                    text   = '==',
                }
            }
        }
        return '=='
    end,
    ErrUEQ = function (start, finish)
        PushError {
            type   = 'ERR_UEQ',
            start  = start,
            finish = finish - 1,
            fix = {
                title = 'FIX_UEQ',
                {
                    start  = start,
                    finish = finish - 1,
                    text   = '~=',
                }
            }
        }
        return '=='
    end,
    ErrThen = function (start, finish)
        PushError {
            type = 'ERR_THEN_AS_DO',
            start = start,
            finish = finish - 1,
            fix = {
                title = 'FIX_THEN_AS_DO',
                {
                    start   = start,
                    finish  = finish - 1,
                    text    = 'then',
                }
            }
        }
        return start, finish
    end,
    ErrDo = function (start, finish)
        PushError {
            type = 'ERR_DO_AS_THEN',
            start = start,
            finish = finish - 1,
            fix = {
                title = 'FIX_DO_AS_THEN',
                {
                    start   = start,
                    finish  = finish - 1,
                    text    = 'do',
                }
            }
        }
        return start, finish
    end,
    MissSpaceBetween = function (start)
        PushError {
            type   = 'MISS_SPACE_BETWEEN',
            start  = start,
            finish = start + 1,
            fix = {
                title = 'FIX_INSERT_SPACE',
                {
                    start   = start + 1,
                    finish  = start,
                    text    = ' ',
                }
            }
        }
    end
}

local function init(state)
    State       = state
    PushError   = state.pushError
    PushDiag    = state.pushDiag
    PushComment = state.pushComment
end

local function close()
    State       = DefaultState
    PushError   = function (...) end
    PushDiag    = function (...) end
    PushComment = function (...) end
end

return {
    defs  = Defs,
    init  = init,
    close = close,
}
