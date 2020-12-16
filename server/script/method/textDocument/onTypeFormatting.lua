local parser = require 'parser'
local config = require 'config'

local function getRange(start, finish, lines)
    local start_row,  start_col  = lines:rowcol(start)
    local finish_row, finish_col = lines:rowcol(finish)
    return {
        start = {
            line = start_row - 1,
            character = start_col - 1,
        },
        ['end'] = {
            line = finish_row - 1,
            -- 这里不用-1，因为前端期待的是匹配完成后的位置
            character = finish_col,
        },
    }
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
    local ast, _, _, missedEnds = parser:parse(text, "Lua")
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
                        character = params.position.character + 1
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
