local guide = require 'core.guide'
local vm    = require 'vm'

local function optionalArg(arg)
    if arg.default then
        return true
    end
    if not arg.bindDocs then
        return false
    end
    local name = arg[1]
    for _, doc in ipairs(arg.bindDocs) do
        if doc.type == 'doc.param' and doc.param[1] == name then
            return doc.optional
        end
    end
end

local function asFunction(source, oop)
    local args = {}
    local methodDef
    local parent = source.parent
    if parent and parent.type == 'setmethod' then
        methodDef = true
    end
    if methodDef then
        args[#args+1] = ('self: %s'):format(vm.getInferType(parent.node))
    end
    if source.args then
        for i = 1, #source.args do
            local arg = source.args[i]
            if arg.dummy then
                goto CONTINUE
            end
            local name = arg.name or guide.getKeyName(arg)
            if arg.type == "..." and arg.typeAnn then
                name = "..."
            end
            local argType = vm.getInferType(arg)
            if name then
                args[#args+1]= ('%s%s: %s'):format(
                    name,
                    optionalArg(arg) and '?' or '',
                    argType
                )
                if arg.default and arg.default ~= "nil" then
                    if argType == "string" or argType:sub(1, 5) == "Enum." then
                        args[#args] = ("%s %s= \"%s\""):format(args[#args], INV, arg.default)
                    else
                        args[#args] = ("%s %s= %s"):format(args[#args], INV, arg.default)
                    end
                end
            else
                args[#args+1] = ('%s'):format(argType)
            end
            ::CONTINUE::
        end
    end
    if oop then
        return table.concat(args, ', ', 2)
    else
        return table.concat(args, ', ')
    end
end

local function asDocFunction(source)
    if not source.args then
        return ''
    end
    local args = {}
    for i = 1, #source.args do
        local arg = source.args[i]
        local name = arg.name[1]
        if arg.extends then
            args[i] = ('%s%s: %s'):format(
                name,
                arg.optional and '?' or '',
                vm.getInferType(arg.extends)
            )
        else
            args[i] = ('%s%s'):format(
                name,
                arg.optional and '?' or ''
            )
        end
    end
    return table.concat(args, ', ')
end

local function asTypeFunction(source, oop)
    local args = {}
    for _, arg in ipairs(source.args) do
        if arg.type == "type.variadic" then
            args[#args+1] = "...: " .. guide.buildTypeAnn(arg.value)
        else
            args[#args+1] = guide.buildTypeAnn(arg)
            if arg.paramName then
                args[#args] = arg.paramName[1] .. ": " .. args[#args]
            else
                args[#args] = "?: " .. args[#args]
            end
        end
        if arg.default then
            args[#args] = ("%s %s= %s"):format(args[#args], INV, (arg.default == "" and '""' or arg.default))
        end
    end
    if oop then
        table.remove(args, 1)
    end
    return table.concat(args, ", ")
end

return function (source, oop)
    if source.type == 'function' then
        return asFunction(source, oop)
    end
    if source.type == 'doc.type.function' then
        return asDocFunction(source)
    end
    if source.type == "type.function" then
        return asTypeFunction(source, oop)
    end
    return ''
end
