local TokenTypes     = require 'constant.TokenTypes'
local TokenModifiers = require 'constant.TokenModifiers'
local resolve        = require 'core.semanticTokens'

local timerCache = {}

local function buildTokens(sources, lines)
    local tokens = {}
    local lastLine = 0
    local lastStartChar = 0
    for i, source in ipairs(sources) do
        local row, col = lines:rowcol(source.start)
        local line = row - 1
        local startChar = col - 1
        local deltaLine = line - lastLine
        local deltaStartChar
        if deltaLine == 0 then
            deltaStartChar = startChar - lastStartChar
        else
            deltaStartChar = startChar
        end
        lastLine = line
        lastStartChar = startChar
        local len = i * 5 - 5
        tokens[len + 1] = deltaLine
        tokens[len + 2] = deltaStartChar
        tokens[len + 3] = source.finish - source.start + 1 -- length
        tokens[len + 4] = source.type
        tokens[len + 5] = source.modifieres or 0
    end
    return tokens
end

local function resolveTokens(vm, lines)
    local sources = {}
    for _, source in ipairs(vm.sources) do
        if resolve.luauTypeSources[source.type] then
            for _, nameType in pairs(resolve.findNameTypes(source.info)) do
                sources[#sources+1] = {
                    start      = nameType.start,
                    finish     = nameType.finish,
                    type       = TokenTypes.type,
                    modifieres = TokenModifiers.static,
                }
            end
        end
        if resolve.Care[source.type] then
            resolve.Care[source.type](source, sources)
        end
    end

    -- 先进行排序
    table.sort(sources, function (a, b)
        return a.start < b.start
    end)

    local tokens = buildTokens(sources, lines)

    return tokens
end

--- @param lsp LSP
--- @param params table
--- @return function
return function (lsp, params)
    local uri = params.textDocument.uri

    if timerCache[uri] then
        timerCache[uri]:remove()
        timerCache[uri] = nil
    end

    return function (response)
        local clock = os.clock()
        timerCache[uri] = ac.loop(0.1, function (t)
            local vm, lines = lsp:getVM(uri)
            if not vm then
                if os.clock() - clock > 10 then
                    t:remove()
                    timerCache[uri] = nil
                    response(nil)
                end
                return
            end
            t:remove()
            timerCache[uri] = nil
            if not vm.sources then
                return
            end
            local tokens = resolveTokens(vm, lines)
            --local tokens = testTokens(vm, lines)
            response {
                data = tokens,
            }
        end)
    end
end
