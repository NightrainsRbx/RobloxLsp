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
--- @return boolean
return function (lsp, params)
    if not (config.isLuau() and config.config.misc.goToScriptLink) then
        return
    end
    local uri = params.textDocument.uri
    local ws = lsp:findWorkspaceFor(uri)
    if not ws then
        return
    end
    local vm, lines = lsp:getVM(uri)
    if not vm then
        return
    end

    local results = {}

    vm:eachSource(function(source)
        if source.type ~= "call" then
            return
        end
        local simple = source:get 'simple'
        if not simple then
            return
        end
        if #simple >= 2 and simple[1][1] == "require" and simple[2].type == "call" then
            local callArgs = simple[2]
            if callArgs[1] and callArgs[1].type == "simple" then
                local value = vm:getFirstInMulti(vm:getSimple(callArgs[1]))
                if value and value._modulePath then
                    local moduleUri = ws:searchPath(uri, value._modulePath)
                    if moduleUri then
                        local start, finish = callArgs[1].start, callArgs[1].finish
                        local last = callArgs[1][#callArgs[1]]
                        if last.type == "name" then
                            start, finish = last.start, last.finish
                        elseif last.type == "call" then
                            if callArgs[1][#callArgs[1] - 1].type == "name" then
                                start, finish = callArgs[1][#callArgs[1] - 1].start, last.finish
                            end
                        end
                        results[#results+1] = {
                            range = getRange(start, finish, lines),
                            tooltip = "Go To Script",
                            target = moduleUri
                        }
                    end
                end
            end
        end
    end)

    return results
end
