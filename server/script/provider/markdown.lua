local mt = {}
mt.__index = mt
mt.__name = 'markdown'

mt._splitLine = false

local function checkSplitLine(self)
    if not self._splitLine then
        return
    end
    self._splitLine = nil
    if #self == 0 then
        return
    end

    self[#self+1] = '\n---'
end

local function splitString(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from, true)
    while delim_from do
        if (delim_from ~= 1) then
            table.insert(result, string.sub(str, from, delim_from-1))
        end
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from, true)
    end
    if (from <= #str) then table.insert(result, string.sub(str, from)) end
    return result
end

function mt:add(language, text)
    if not text or #text == 0 then
        return
    end

    checkSplitLine(self)

    if language == 'md' then
        if self._last == 'md' then
            self[#self+1] = ''
        end
        local formattedLines = {}
        local lines = splitString(text:gsub("\r", ""), "\n")
        local indent = #(lines[1] or ""):match('^%s*')
        for _, line in ipairs(lines) do
            formattedLines[#formattedLines+1] = line:sub(indent + 1)
        end
        self[#self+1] =  table.concat(formattedLines, "\n")
    else
        if #self > 0 then
            self[#self+1] = ''
        end
        self[#self+1] = ('```%s\n%s\n```'):format(language, text)
    end

    self._last = language
end

function mt:string()
    return table.concat(self, '\n')
end

function mt:splitLine()
    self._splitLine = true
end

return function ()
    return setmetatable({}, mt)
end
