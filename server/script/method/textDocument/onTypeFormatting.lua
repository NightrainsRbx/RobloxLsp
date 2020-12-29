local parser = require 'parser'
local config = require 'config'

local function findKeywordOrParen(text, offset)
    for i = offset, 1, -1 do
        if not text:sub(i, i):match '[%w%)]' then
            if i == offset then
                return nil
            end
            return text:sub(i+1, offset)
        end
    end
    return text:sub(1, offset)
end

--- @param lsp LSP
--- @param params table
--- @return any
return function (lsp, params)
    if not config.config.completion.endAutocompletion then
        return
    end
    local uri = params.textDocument.uri
    local text = lsp:getText(uri)
    local lines = parser:lines(text, 'utf8')
    local position = lines:position(params.position.line + 1, params.position.character)
    local offset = text:sub(1, position):find("\r\n[\t ]*$")
    local key = findKeywordOrParen(text, offset - 1)
    if key ~= "then" and key ~= "do" and key ~= ")" then
        return
    end
    local _, _, _, missedEnds = parser:parse(text, "Lua")
    local action, closer = nil, 0
    for _, source in pairs(missedEnds) do
        if position > source.start and position > source.finish and source.finish > closer then
            action, closer = source, source.finish
        end
    end
    if not action then
        return nil
    end
    local startLine = lines[params.position.line]
    local spaces = ""
    if startLine.tab > 0 then
        spaces = string.rep("\t", startLine.tab)
    else
        spaces = string.rep(" ", startLine.sp)
    end
    if params.position.line + 1 == #lines then
        return {
            {
                range = {
                    start = {
                        line = params.position.line,
                        character = 0
                    },
                    ["end"] = {
                        line = params.position.line,
                        character = params.position.character + 1
                    }
                },
                newText = "\nend"
            }
        }
    else
        return {
            {
                range = {
                    start = {
                        line = params.position.line + 1,
                        character = 0
                    },
                    ["end"] = {
                        line = params.position.line + 1,
                        character = 0
                    }
                },
                newText = spaces .. "end\n"
            }
        }
    end
end
