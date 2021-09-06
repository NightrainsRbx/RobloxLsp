local files = require 'files'
local guide = require 'core.guide'
local vm = require 'vm'
local ws         = require 'workspace'
local furi       = require 'file-uri'
local rojo       = require 'library.rojo'

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
                    if def.path then
                        local path = rojo:findPathByScript(def)
                        if path then
                            local moduleUri = ws.findUrisByRequirePath(path)[1]
                            if moduleUri then
                                results[#results+1] = {
                                    range = files.range(uri, source.args[1].start, source.args[1].finish),
                                    tooltip = "Go To Script",
                                    target = moduleUri
                                }
                                return
                            end
                        end
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