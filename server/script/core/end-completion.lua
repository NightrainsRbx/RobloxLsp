local files    = require 'files'
local guide     = require 'core.guide'
local proto  = require 'proto'

local accept = {
    ["ifblock"] = true,
    ["function"] = true,
    ["do"] = true,
    ["while"] = true,
    ["in"] = true,
    ["loop"] = true,
}

return function (uri, position)
    local ast = files.getAst(uri)
    if (not ast) or #ast.errs == 0 then
        return
    end
    local lines = files.getLines(uri)
    local text  = files.getText(uri)
    local offset = files.offset(uri, position)
    local finishOffset = text:sub(1, offset - 1):find("\r?\n[\t ]*$")
    if not finishOffset then
        return
    end
    local source = guide.eachSourceContain(ast.ast, finishOffset - 1, function(source)
        if accept[source.type] then
            if (source.argsFinish or source.finish) == finishOffset - 1 then
                return source
            elseif source.keyword then
                for _, keyword in ipairs(source.keyword) do
                    if keyword == finishOffset - 1 then
                        return source
                    end
                end
            end
        end
    end)
    if not source then
        return
    end
    local missEnd = false
    for _, err in ipairs(ast.errs) do
        if err.type == "MISS_SYMBOL"
        and err.info
        and (err.info.symbol == "end" or err.info.symbol == ")")
        and err.finish > source.finish then
            missEnd = true
            break
        end
    end
    if not missEnd then
        return
    end
    if position.line + 1 == #lines then
        proto.awaitRequest('workspace/applyEdit', {
            label = 'add end',
            edit  = {
                changes = {
                    [uri] = {
                        {
                            range = {
                                start = {
                                    line = position.line,
                                    character = 0,
                                },
                                ["end"] = {
                                    line = position.line,
                                    character = position.character + 1
                                }
                            },
                            newText = "\nend" .. text:sub(offset, offset)
                        }
                    }
                }
            }
        })
        proto.notify('$/command', {
            command = "cursorMove",
            data = {
                to = "prevBlankLine"
            }
        })
    else
        local startLine = lines[position.line]
        local spaces = ""
        if startLine.tab > 0 then
            spaces = string.rep("\t", startLine.tab)
        else
            spaces = string.rep(" ", startLine.sp)
        end
        proto.awaitRequest('workspace/applyEdit', {
            label = 'add end',
            edit  = {
                changes = {
                    [uri] = {
                        {
                            range = {
                                start = {
                                    line = position.line,
                                    character = position.character + 1
                                },
                                ["end"] = {
                                    line = position.line + 1,
                                    character = 0
                                }
                            },
                            newText = "\n" .. spaces .. "end" .. text:sub(offset):match("(.-)\n") .. "\n"
                        },
                        {
                            range = {
                                start = {
                                    line = position.line,
                                    character = position.character
                                },
                                ["end"] = {
                                    line = position.line,
                                    character = position.character + 1
                                },
                                newText = ""
                            }
                        }
                    }
                }
            }
        })
    end
end
