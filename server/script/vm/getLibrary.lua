---@type vm
local vm          = require 'vm.vm'
local rbxlibs     = require 'library.rbxlibs'

function vm.getLibraryName(source, deep)
    local defs = vm.getDefs(source, deep)
    for _, def in ipairs(defs) do
        if def.special then
            return def.special
        end
    end
    return nil
end

function vm.isGlobalLibraryName(name)
    if rbxlibs.global[name] then
        return true
    end
end
