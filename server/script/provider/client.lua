local nonil = require 'without-check-nil'
local util  = require 'utility'
local lang  = require 'language'

local m = {}

function m.client(newClient)
    if newClient then
        m._client = newClient
    else
        return m._client
    end
end

function m.isVSCode()
    if not m._client then
        return false
    end
    if m._isvscode == nil then
        local lname = m._client:lower()
        if lname:find 'vscode'
        or lname:find 'visual studio code' then
            m._isvscode = true
        else
            m._isvscode = false
        end
    end
    return m._isvscode
end

function m.getAbility(name)
    if not m.info
    or not m.info.capabilities then
        return nil
    end
    local current = m.info.capabilities
    while true do
        local parent, nextPos = name:match '^([^%.]+)()'
        if not parent then
            break
        end
        current = current[parent]
        if not current then
            return nil
        end
        if nextPos > #name then
            break
        else
            name = name:sub(nextPos + 1)
        end
    end
    return current
end

function m.getOffsetEncoding()
    if m._offsetEncoding then
        return m._offsetEncoding
    end
    local clientEncodings = m.getAbility 'offsetEncoding'
    if type(clientEncodings) == 'table' then
        for _, encoding in ipairs(clientEncodings) do
            if encoding == 'utf-8' then
                m._offsetEncoding = 'utf-8'
                return m._offsetEncoding
            end
        end
    end
    m._offsetEncoding = 'utf-16'
    return m._offsetEncoding
end

function m.init(t)
    log.debug('Client init', util.dump(t))
    m.info = t
    nonil.enable()
    m.client(t.clientInfo.name)
    nonil.disable()
    lang(LOCALE or t.locale)
end

return m
