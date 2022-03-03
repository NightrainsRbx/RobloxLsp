local files     = require 'files'
local guide     = require 'core.guide'
local vm        = require 'vm'
local config    = require 'config'
local getReturn = require 'core.hover.return'
local util      = require 'utility'

local function typeHint(uri, edits, start, finish)
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    local mark = {}
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        if  source.type ~= 'local'
        and source.type ~= 'setglobal'
        and source.type ~= 'tablefield'
        and source.type ~= 'tableindex'
        and source.type ~= 'setfield'
        and source.type ~= 'setindex' then
            return
        end
        if source.typeAnn then
            return
        end
        if source[1] == '_' then
            return
        end
        if source.value and guide.isLiteral(source.value) then
            return
        end
        if source.parent.type == 'funcargs' then
            if not config.config.hint.paramType then
                return
            end
        elseif source.type == "local" then
            if not config.config.hint.variableType then
                return
            end
        elseif not config.config.hint.setType then
            return
        end
        local infer = vm.getInferType(source, 0)
        if not source.value or (infer == 'any' or infer == 'nil') then
            return
        end
        if #infer > 30 then
            infer = infer:sub(1, 30) .. "..."
        end
        local src = source
        if source.type == 'tablefield' then
            src = source.field
        elseif source.type == 'tableindex' then
            src = source.index
        end
        if not src then
            return
        end
        if mark[src] then
            return
        end
        mark[src] = true
        edits[#edits+1] = {
            newText = (': %s'):format(infer),
            start   = src.finish,
            finish  = src.finish,
        }
    end)
end

local function getArgNames(func)
    if not func.args or #func.args == 0 then
        return nil
    end
    local names = {}
    -- if func.parent and func.parent.type == 'setmethod' then
    --     names[#names+1] = 'self'
    -- end
    for _, arg in ipairs(func.args) do
        if arg.type == '...' or arg.type == "type.variadic" then
            break
        end
        if guide.isTypeAnn(arg) then
            names[#names+1] = (arg.paramName and arg.paramName[1]) or ''
        else
            names[#names+1] = arg[1] or ''
        end
    end
    if #names == 0 then
        return nil
    end
    return names
end

local function hasLiteralArgInCall(call)
    if not call.args then
        return false
    end
    for _, arg in ipairs(call.args) do
        if guide.isLiteral(arg) then
            return true
        end
    end
    return false
end

local function paramName(uri, edits, start, finish)
    if not config.config.hint.paramName then
        return
    end
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    local text = files.getText(uri)
    local mark = {}
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        if source.type ~= 'call' or not source.args then
            return
        end
        -- if not hasLiteralArgInCall(source) then
        --     return
        -- end
        local defs = vm.getDefs(source.node, 0)
        if not defs then
            return
        end
        local args
        for _, def in ipairs(defs) do
            def = guide.getObjectValue(def) or def
            if def.type == 'function'
            or def.type == 'type.function' then
                args = getArgNames(def)
                if args then
                    break
                end
            end
        end
        if not args then
            return
        end
        if source.node and source.node.type == 'getmethod' then
            mark[source.args[1]] = true
        end
        for i, arg in ipairs(source.args) do
            if not mark[arg] and arg.type ~= "varargs" then--and guide.isLiteral(arg) then
                mark[arg] = true
                if args[i] and args[i] ~= '' and text:sub(source.args[i].start, source.args[i].finish) ~= args[i] then
                    edits[#edits+1] = {
                        newText = ('%s:'):format(args[i]),
                        start   = arg.start,
                        finish  = arg.start - 1,
                    }
                end
            end
        end
    end)
end

local function returnType(uri, edits, start, finish)
    if not config.config.hint.returnType then
        return
    end
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    guide.eachSourceBetween(ast.ast, start, finish, function (source)
        if source.type ~= "function" then
            return
        end
        if source.returnTypeAnn then
            return
        end
        local rtnText = getReturn(source)
        if not rtnText then
            return
        end
        local returns = {}
        for rtn in util.eachLine(rtnText) do
            returns[#returns+1] = rtn:match("[ ]+.- (.+)$")
        end
        if #returns == 1 then
            returns = returns[1]
        else
            returns = ("(%s)"):format(table.concat(returns, ", "))
        end
        if #returns > 30 then
            returns = returns:sub(1, 30) .. "..."
        end
        edits[#edits+1] = {
            newText = (": %s"):format(returns),
            start   = source.argsFinish,
            finish  = source.argsFinish,
        }
    end)
end

return function (uri, start, finish)
    local edits = {}
    typeHint(uri, edits, start, finish)
    paramName(uri, edits, start, finish)
    returnType(uri, edits, start, finish)
    return edits
end
