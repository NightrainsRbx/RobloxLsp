local files   = require 'files'
local guide   = require 'core.guide'
local lang    = require 'language'
local rbxlibs = require 'library.rbxlibs'
local vm      = require 'vm'

return function (uri, callback)
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    guide.eachSourceType(ast.ast, 'callargs', function (source)
        local func = source.parent.node
        if func.special == "type" or func.special == "typeof" then
            local parent = source.parent.parent
            if parent.type == "binary"
            and (parent.op.type == "==" or parent.op.type == "~=")
            and parent[2].type == "string" then
                for _, enum in pairs(rbxlibs.global[func.special].value.enums) do
                    if enum.text == "\"" .. parent[2][1] .. "\"" then
                        return
                    end
                end
                callback {
                    start   = parent[2].start,
                    finish  = parent[2].finish,
                    message = lang.script('DIAG_INVALID_CLASSNAME', (func.special == "type" and "primitive " or "") .. "type", parent[2][1]),
                }
            end
        end
        if (not source[1] or source[1].type ~= "string") and (not source[2] or source[2].type ~= "string") then
            return
        end
        for _, def in ipairs(vm.getDefs(func, 0)) do
            if def.special == "Instance.new"
            or def.special == "Roact.createElement" then
                local arg = source[1]
                if arg and arg.type == "string" and not rbxlibs.CreatableInstances[arg[1]] then
                    callback {
                        start   = arg.start,
                        finish  = arg.finish,
                        message = lang.script('DIAG_INVALID_CLASSNAME', "Creatable Instance", arg[1]),
                    }
                end
                break
            elseif def.special == "GetService" then
                local arg = source[2]
                if arg and arg.type == "string" and not rbxlibs.Services[arg[1]] then
                    callback {
                        start   = arg.start,
                        finish  = arg.finish,
                        message = lang.script('DIAG_INVALID_CLASSNAME', "Service", arg[1]),
                    }
                end
                break
            elseif def.special == "FindFirstClass" or def.special == "IsA" then
                local arg = source[2]
                if arg and arg.type == "string" and not rbxlibs.ClassNames[arg[1]] then
                    callback {
                        start   = arg.start,
                        finish  = arg.finish,
                        message = lang.script('DIAG_INVALID_CLASSNAME', "Instance", arg[1]),
                    }
                end
                break
            elseif def.special == "EnumItem.IsA" then
                local arg = source[2]
                if arg and arg.type == "string" and not rbxlibs.Enums[arg[1]] then
                    callback {
                        start   = arg.start,
                        finish  = arg.finish,
                        message = lang.script('DIAG_INVALID_CLASSNAME', "Enum", arg[1]),
                    }
                end
                break
            elseif def.special == "BrickColor.new" then
                local arg = source[1]
                if arg and arg.type == "string" and not rbxlibs.BrickColors[arg[1]] then
                    callback {
                        start   = arg.start,
                        finish  = arg.finish,
                        message = lang.script('DIAG_INVALID_CLASSNAME', "BrickColor", arg[1]),
                    }
                end
                break
            end
        end
    end)
end
