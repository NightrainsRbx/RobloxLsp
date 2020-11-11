local ignore = {}

local function stringify(key, tab, level)
    if ignore[tostring(tab)] then
        return ignore[tostring(tab)]
    end
    ignore[tostring(tab)] = tostring(key) .. "{" .. tostring(tab) .. "}"
    level = level or 0
    local str = ""
    for index, value in pairs(tab) do
        if index == "_manager" or index == "emmyMgr" or index == "@ENV" or index == "enums" then
            value = index
        end
        if type(value) == "table" then
            str = str .. "\n" .. string.rep("   ", level) .. tostring(index) .. ": " .. stringify(index, value, level + 1)
        else
            str = str .. "\n" .. string.rep("   ", level) .. tostring(index) .. ": " .. tostring(value)
        end
    end
    return str
end

return function(mode, ...)
    ignore = {}
    local strs = {}
    for index, str in pairs{...} do
        if type(str) == "table" then
            table.insert(strs, stringify(index, str))
        else
            table.insert(strs, tostring(str))
        end
    end
    local output = table.concat(strs, "\n") .. "\n"

    local file = io.open("C:\\Users\\andre\\output.txt", mode)
    file:write(output)
    file:close()
end