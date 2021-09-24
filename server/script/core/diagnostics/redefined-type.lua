local files = require 'files'
local guide = require 'core.guide'
local lang  = require 'language'
local rbxlibs = require 'library.rbxlibs'
local vm = require 'vm'

local function checkSelfRecursiveTypeAlias(typeAlias, value, mark)
    mark = mark or {}
    if mark[value] then
        return true
    end
    mark[value] = true
    if value.type == "type.union" or value.type == "type.inter" then
        for _, v in ipairs(guide.getAllValuesInType(value)) do
            if checkSelfRecursiveTypeAlias(typeAlias, v, mark) then
                return true
            end
        end
    end
    if value.typeAlias then
        if value.typeAlias == typeAlias then
            return true
        end
        return checkSelfRecursiveTypeAlias(typeAlias, value.typeAlias.value, mark)
    end
    return false
end

return function (uri, callback)
    local ast   = files.getAst(uri)
    if not ast then
        return
    end
    guide.eachSourceType(ast.ast, "type.alias", function (source)
        if checkSelfRecursiveTypeAlias(source, source.value) then
            callback {
                start = source.start,
                finish = source.finish,
                message = lang.script('TYPE_ALIAS_RECURSIVE')
            }
            return
        end
        local other = guide.getTypeAliasInAst(source, source.name[1])
        if other and other ~= source then
            callback {
                start = source.name.start,
                finish = source.name.finish,
                message = lang.script('TYPE_REDEFINED', source.name[1]),
                related = {
                    {
                        start = other.start,
                        finish = other.finish,
                        uri = guide.getUri(other)
                    }
                }
            }
        end
        if source.generics then
            local names = {}
            for _, generic in ipairs(source.generics) do
                local other = guide.getTypeAliasInAst(source, generic[1])
                if other then
                    callback {
                        start = generic.start,
                        finish = generic.finish,
                        message = lang.script('TYPE_REDEFINED', generic[1]),
                        related = {
                            {
                                start = other.start,
                                finish = other.finish,
                                uri = guide.getUri(other)
                            }
                        }
                    }
                end
                if names[generic[1]] then
                    callback {
                        start = generic.start,
                        finish = generic.finish,
                        message = lang.script('TYPE_REDEFINED', generic[1]),
                        related = {
                            {
                                start = names[generic[1]].start,
                                finish = names[generic[1]].finish,
                                uri = uri
                            }
                        }
                    }
                end
                names[generic[1]] = generic
            end
        end
    end)
end