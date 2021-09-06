local files = require 'files'
local guide = require 'core.guide'
local vm = require 'vm'

return function (uri)
    local ast = files.getAst(uri)
    if not ast then
        return
    end
    local results = {}
    guide.eachSourceType(ast.ast, "call", function(source)
        if source.node.special == "require" then
            if source.args and source.args[1] then
                local defs = vm.getDefs(source.args[1])
                for _, def in ipairs(defs) do
                    if def.uri then
                        results[#results+1] = {
                            range = files.range(uri, source.args[1].start, source.args[1].finish),
                            tooltip = "Go To Script",
                            target = def.uri
                        }
                    end
                end
            end
        end
    end)
    if #results == 0 then
        return nil
    end
    return results
end