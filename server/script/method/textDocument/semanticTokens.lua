local TokenTypes     = require 'constant.TokenTypes'
local TokenModifiers = require 'constant.TokenModifiers'
local findLib        = require 'core.find_lib'
local rbxapi         = require 'rbxapi'
local config         = require 'config'

local timerCache = {}
local constLib = {
    ['_G']                = true,
    ['_VERSION']          = true,
    ['math.pi']           = true,
    ['math.huge']         = true,
    ['math.maxinteger']   = true,
    ['math.mininteger']   = true,
    ['utf8.charpattern']  = true,
    ['io.stdin']          = true,
    ['io.stdout']         = true,
    ['io.stderr']         = true,
    ['package.config']    = true,
    ['package.cpath']     = true,
    ['package.loaded']    = true,
    ['package.loaders']   = true,
    ['package.path']      = true,
    ['package.preload']   = true,
    ['package.searchers'] = true,
    ['workspace']         = true,
    ['game']              = true,
    ['script']            = true,
    ['plugin']            = true,
    ['shared']            = true,
    -- ['Enum']              = true,
}

-- Return true from func to not descend the AST further
-- TODO: There should be an actual ast visitor which has more awareness of the
-- AST structure, this is a quick hack.
local function walkAst(root, func)
    if not func(root) then
        for i, part in pairs(root) do
            if type(i) == "number" or (type(i) == "string" and i:sub(1, 1) ~= "_") then
                if type(part) == "table" and part.type then
                    walkAst(part, func)
                end
            end
        end
    end
end

local Care;

local function walkAstFindingSemanticTokens(source, sources)
    walkAst(source, function(node)
        if Care[node.type] then
            return Care[node.type](node, sources)
        end
    end)
end

Care = {
    ['name'] = function(source, sources)
        if source[1] == '' then
            return
        end
        if constLib[source[1]] then
            return
        end
        if not source.get then
            return
        end
        if source:get 'global' then
            if rbxapi.Constructors[source[1]] then
                sources[#sources+1] = {
                    start      = source.start,
                    finish     = source.finish,
                    type       = TokenTypes.class,
                    modifieres = TokenModifiers.static,
                }
                return
            end
            local lib = findLib(source)
            if lib then
                if lib.type == "Enums" then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.enum,
                        modifieres = TokenModifiers.static,
                    }
                    return
                end
                sources[#sources+1] = {
                    start      = source.start,
                    finish     = source.finish,
                    type       = TokenTypes.namespace,
                    modifieres = TokenModifiers.static,
                }
                return
            end
            sources[#sources+1] = {
                start      = source.start,
                finish     = source.finish,
                type       = TokenTypes.namespace,
                modifieres = TokenModifiers.deprecated,
            }
        -- elseif source:get 'table index' then
        --     sources[#sources+1] = {
        --         start      = source.start,
        --         finish     = source.finish,
        --         type       = TokenTypes.property,
        --         modifieres = TokenModifiers.declaration,
        --     }
        elseif source:bindLocal() then
            if source:get 'arg' then
                sources[#sources+1] = {
                    start      = source.start,
                    finish     = source.finish,
                    type       = TokenTypes.parameter,
                    modifieres = TokenModifiers.declaration,
                }
            end
            if source[1] == '_ENV'
            or source[1] == 'self' then
                return
            end
            local value = source:bindValue()
            local func = value:getFunction()
            if func and func:getSource().name == source then
                sources[#sources+1] = {
                    start      = source.start,
                    finish     = source.finish,
                    type       = TokenTypes.interface,
                    modifieres = TokenModifiers.declaration,
                }
                return
            end
            -- sources[#sources+1] = {
            --     start      = source.start,
            --     finish     = source.finish,
            --     type       = TokenTypes.variable,
            -- }
        elseif source:bindValue() then
            local value = source:bindValue()
            if value:getType():sub(1, 4) == "Enum" then
                local simple = source:get("simple")
                if simple and simple[1] and simple[1][1] == "Enum" then
                    sources[#sources+1] = {
                        start      = source.start,
                        finish     = source.finish,
                        type       = TokenTypes.enum,
                        modifieres = TokenModifiers.static,
                    }
                end
            end
        end
    end,
    ['emmyName'] = function(source, sources)
        if source[1] == '' or not source.syntax then
            return
        end
        sources[#sources+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.type,
            modifieres = TokenModifiers.static,
        }
    end,
    ['typeList'] = function(source, sources)
        for _, ty in ipairs(source.types) do
            walkAstFindingSemanticTokens(ty, sources)
        end
    end,
    ['nameType'] = function(source, sources)
        sources[#sources+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.type,
            modifieres = TokenModifiers.static,
        }
    end,
    ['indexType'] = function(source, sources)
        sources[#sources+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.type,
            modifieres = TokenModifiers.static,
        }
    end,
    ['number'] = function(source, sources)
        sources[#sources+1] = {
            start      = source.start,
            finish     = source.finish,
            type       = TokenTypes.number,
            modifieres = TokenModifiers.static,
        }
    end
}

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
        walkAstFindingSemanticTokens(source, sources)
    end

    -- 先进行排序
    table.sort(sources, function (a, b)
        return a.start < b.start
    end)

    local tokens = buildTokens(sources, lines)

    return tokens
end

local function toArray(map)
    local array = {}
    for k in pairs(map) do
        array[#array+1] = k
    end
    table.sort(array, function (a, b)
        return map[a] < map[b]
    end)
    return array
end

local function testTokens(vm, lines)
    local text = vm.text
    local sources = {}
    local init = 1
    while true do
        local start, finish = text:find('[%w_%.]+', init)
        if not start then
            break
        end
        init = finish + 1
        local token = text:sub(start, finish)
        local type = token:match '[%w_]+'
        local mod  = token:match '%.([%w_]+)'
        sources[#sources+1] = {
            start      = start,
            finish     = finish,
            type       = TokenTypes[type],
            modifieres = TokenModifiers[mod] or 0,
        }
    end
    local tokens = buildTokens(sources, lines)
    log.debug(table.dump(sources))
    log.debug(table.dump(tokens))
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

            local tokens = resolveTokens(vm, lines)
            --local tokens = testTokens(vm, lines)
            response {
                data = tokens,
            }
        end)
    end
end
