---@type vm
local vm    = require 'vm.vm'
local guide = require 'core.guide'
local files = require 'files'

function vm.getTypeString(source, deep)
    local infers = vm.getInfers(source, deep)
    if #infers == 1 then
        local infer = infers[1]
        if infer.source and infer.source.type == "type.table" then
            local fields = {}
            for _, field in ipairs(infer.source) do
                fields[#fields+1] = "\t" .. guide.buildTypeAnn(field)
            end
            return ("{\n%s\n}"):format(table.concat(fields, ",\n"))
        end
    end
    return guide.viewInferType(infers)
end

function vm.getModuleTypeAlias(source)
    local module = source[1]
    local myUri = guide.getUri(source)
    for _, def in ipairs(vm.getDefs(module, 0, {skipType = true})) do
        local uri = guide.getUri(def)
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
    return nil
end