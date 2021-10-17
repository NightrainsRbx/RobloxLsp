---@type vm
local vm          = require 'vm.vm'
local guide       = require 'core.guide'
local files       = require 'files'
local defaultlibs = require 'library.defaultlibs'

function vm.getTypeString(source, deep)
    local infers = vm.getInfers(source, deep)
    if #infers == 1 then
        local infer = infers[1]
        if infer.source and infer.source.type == "type.table" then
            local fields = {}
            for _, field in ipairs(infer.source) do
                fields[#fields+1] = "    " .. guide.buildTypeAnn(field)
            end
            return ("{\n%s\n}"):format(table.concat(fields, ",\n"))
        end
    end
    return guide.viewInferType(infers)
end

function vm.getTypeAlias(source)
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
    if source.type == "type.module" then
        local module = source[1]
        local myUri = guide.getUri(source)
        for _, def in ipairs(vm.getDefs(module, 0, {skipType = true})) do
            local uri = guide.getUri(def)
            if not files.eq(myUri, uri) then
                local ast = files.getAst(uri)
                if ast and ast.ast.types then
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
        local uri = guide.getUri(source)
        if uri and not files.isLibrary(uri) then
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
        for _, alias in pairs(defaultlibs.customType) do
            if alias.name[1] == source[1] then
                return alias
            end
        end
    end
    return nil
end